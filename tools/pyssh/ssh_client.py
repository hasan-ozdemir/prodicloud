#!/usr/bin/env python3
import argparse
import json
import sys
import time
import uuid
import threading
from pathlib import Path
from typing import Optional

sys.dont_write_bytecode = True


SCRIPT_DIR = Path(__file__).resolve().parent
VENDOR_DIR = SCRIPT_DIR / "vendor"
if VENDOR_DIR.exists():
    sys.path.insert(0, str(VENDOR_DIR))

import paramiko  # type: ignore


def configure_stdio() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def write_text(stream, text: str) -> None:
    value = "" if text is None else str(text)
    try:
        stream.write(value)
        stream.flush()
        return
    except Exception:
        pass

    stream_buffer = getattr(stream, "buffer", None)
    if stream_buffer is not None:
        try:
            stream_buffer.write(value.encode("utf-8", errors="replace"))
            stream_buffer.flush()
            return
        except Exception:
            pass

    try:
        ascii_text = value.encode("ascii", errors="replace").decode("ascii")
        stream.write(ascii_text)
        stream.flush()
    except Exception:
        pass


def write_stdout(text: str) -> None:
    write_text(sys.stdout, text)


def write_stderr(text: str) -> None:
    write_text(sys.stderr, text)


def sanitize_stream_text(text: str) -> str:
    if text is None:
        return ""
    value = str(text).replace("\x00", "")
    if value.startswith("\ufeff"):
        value = value.lstrip("\ufeff")
    return value


def clamp_int(value: int, minimum: int, maximum: int, default: int) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = int(default)
    return max(minimum, min(maximum, parsed))


def build_client(
    host: str,
    port: int,
    user: str,
    password: str,
    timeout: int,
    keepalive_seconds: int = 15,
) -> paramiko.SSHClient:
    connect_timeout = max(5, min(int(timeout), 60)) if timeout > 0 else 30
    keepalive = clamp_int(keepalive_seconds, 5, 120, 15)
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=host,
        port=port,
        username=user,
        password=password,
        timeout=connect_timeout,
        banner_timeout=connect_timeout,
        auth_timeout=connect_timeout,
        look_for_keys=False,
        allow_agent=False,
    )
    transport = client.get_transport()
    if transport is not None:
        transport.set_keepalive(keepalive)
    return client


def reconnect_client(current_client: Optional[paramiko.SSHClient], args: argparse.Namespace) -> paramiko.SSHClient:
    if current_client is not None:
        try:
            current_client.close()
        except Exception:
            pass

    return build_client(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        timeout=args.timeout,
        keepalive_seconds=args.keepalive_seconds,
    )


def run_exec(args: argparse.Namespace) -> int:
    stdin_path = None
    stdin_offset = 0
    stdin_length = -1
    if getattr(args, "stdin_file", None):
        stdin_path = Path(args.stdin_file).expanduser().resolve()
        if not stdin_path.exists():
            write_stderr(f"STDIN file was not found: {stdin_path}\n")
            return 2
        try:
            stdin_offset = max(0, int(getattr(args, "stdin_file_offset", 0) or 0))
        except Exception:
            stdin_offset = 0
        try:
            stdin_length = int(getattr(args, "stdin_file_length", -1) or -1)
        except Exception:
            stdin_length = -1
        if stdin_length < 0:
            stdin_length = -1

        file_size = stdin_path.stat().st_size
        if stdin_offset > file_size:
            write_stderr(f"STDIN file offset is beyond EOF: {stdin_offset} > {file_size}\n")
            return 2
        if stdin_length >= 0:
            stdin_length = min(stdin_length, max(0, file_size - stdin_offset))

    client = build_client(
        args.host,
        args.port,
        args.user,
        args.password,
        args.timeout,
        args.keepalive_seconds,
    )
    try:
        transport = client.get_transport()
        if transport is None:
            write_stderr("SSH transport could not be created.\n")
            return 2

        channel = transport.open_session()
        channel.exec_command(args.command)

        deadline = None
        if int(args.timeout) > 0:
            deadline = time.monotonic() + int(args.timeout)

        if stdin_path is not None:
            with stdin_path.open("rb") as stdin_handle:
                if stdin_offset > 0:
                    stdin_handle.seek(stdin_offset)
                remaining = stdin_length
                while True:
                    if deadline is not None and time.monotonic() >= deadline:
                        channel.close()
                        write_stderr(f"SSH command timed out after {args.timeout} second(s).\n")
                        return 124

                    if remaining == 0:
                        break

                    read_size = 65536
                    if remaining > 0:
                        read_size = min(read_size, remaining)

                    chunk = stdin_handle.read(read_size)
                    if not chunk:
                        break
                    if remaining > 0:
                        remaining -= len(chunk)

                    pending = memoryview(chunk)
                    while len(pending) > 0:
                        if deadline is not None and time.monotonic() >= deadline:
                            channel.close()
                            write_stderr(f"SSH command timed out after {args.timeout} second(s).\n")
                            return 124

                        if channel.closed:
                            write_stderr("SSH channel closed while streaming stdin.\n")
                            return 3

                        sent = channel.send(pending)
                        if sent is None:
                            sent = 0
                        if sent <= 0:
                            time.sleep(0.05)
                            continue
                        pending = pending[sent:]

            try:
                channel.shutdown_write()
            except Exception:
                pass

        stdout_chunks = []
        stderr_chunks = []

        while True:
            while channel.recv_ready():
                chunk = channel.recv(65536)
                stdout_chunks.append(chunk)
                write_stdout(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
            while channel.recv_stderr_ready():
                chunk = channel.recv_stderr(65536)
                stderr_chunks.append(chunk)
                write_stderr(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))

            if channel.exit_status_ready():
                break

            if deadline is not None and time.monotonic() >= deadline:
                channel.close()
                write_stderr(f"SSH command timed out after {args.timeout} second(s).\n")
                return 124

            time.sleep(0.2)

        while channel.recv_ready():
            chunk = channel.recv(65536)
            stdout_chunks.append(chunk)
            write_stdout(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
        while channel.recv_stderr_ready():
            chunk = channel.recv_stderr(65536)
            stderr_chunks.append(chunk)
            write_stderr(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))

        out = b"".join(stdout_chunks).decode("utf-8", errors="replace")
        err = b"".join(stderr_chunks).decode("utf-8", errors="replace")
        exit_code = channel.recv_exit_status()
        return int(exit_code)
    finally:
        client.close()


def run_copy(args: argparse.Namespace) -> int:
    local_path = Path(args.local).expanduser().resolve()
    if not local_path.exists():
        write_stderr(f"Local file was not found: {local_path}\n")
        return 2

    client = build_client(
        args.host,
        args.port,
        args.user,
        args.password,
        args.timeout,
        args.keepalive_seconds,
    )
    try:
        sftp = client.open_sftp()
        try:
            sftp.put(str(local_path), args.remote)
        finally:
            sftp.close()
        return 0
    finally:
        client.close()


def run_fetch(args: argparse.Namespace) -> int:
    local_path = Path(args.local).expanduser().resolve()
    local_parent = local_path.parent
    local_parent.mkdir(parents=True, exist_ok=True)

    client = build_client(
        args.host,
        args.port,
        args.user,
        args.password,
        args.timeout,
        args.keepalive_seconds,
    )
    try:
        sftp = client.open_sftp()
        try:
            sftp.get(args.remote, str(local_path))
        finally:
            sftp.close()
        return 0
    finally:
        client.close()


def run_shell(args: argparse.Namespace) -> int:
    client = build_client(
        args.host,
        args.port,
        args.user,
        args.password,
        args.timeout,
        args.keepalive_seconds,
    )
    try:
        transport = client.get_transport()
        if transport is None or not transport.is_active():
            write_stderr("SSH transport could not be created.\n")
            return 2

        channel = transport.open_session()
        try:
            channel.get_pty(term="xterm", width=160, height=48)
        except Exception:
            # Some SSH servers may reject PTY resize details; continue with defaults.
            channel.get_pty()
        channel.invoke_shell()

        selected_shell = str(getattr(args, "shell", "") or "").strip().lower()
        initial_command = ""
        if selected_shell == "powershell":
            initial_command = "powershell -NoProfile -NoLogo"
        elif selected_shell == "cmd":
            initial_command = "cmd"
        elif selected_shell == "bash":
            initial_command = "bash"
        if initial_command:
            channel.send(initial_command + "\n")

        stop_event = threading.Event()
        stdin_error = {"value": None}

        def _stdin_pump() -> None:
            try:
                while not stop_event.is_set():
                    line = sys.stdin.readline()
                    if line == "":
                        break
                    if channel.closed:
                        break
                    channel.send(line)
            except Exception as exc:  # pragma: no cover - defensive runtime protection
                stdin_error["value"] = exc
            finally:
                try:
                    channel.shutdown_write()
                except Exception:
                    pass

        stdin_thread = threading.Thread(target=_stdin_pump, daemon=True)
        stdin_thread.start()

        while True:
            had_output = False
            while channel.recv_ready():
                chunk = channel.recv(65536)
                if chunk:
                    write_stdout(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
                    had_output = True

            while channel.recv_stderr_ready():
                chunk = channel.recv_stderr(65536)
                if chunk:
                    write_stderr(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
                    had_output = True

            if channel.closed:
                break
            if channel.exit_status_ready():
                break
            if stop_event.is_set():
                break

            if not had_output:
                time.sleep(0.05)

        stop_event.set()
        try:
            stdin_thread.join(timeout=0.5)
        except Exception:
            pass

        if stdin_error["value"] is not None:
            write_stderr(f"stdin forwarding failed: {stdin_error['value']}\n")
            return 1

        if channel.exit_status_ready():
            return int(channel.recv_exit_status())
        return 0
    finally:
        client.close()


def resolve_session_command(shell_name: str) -> str:
    shell = (shell_name or "").strip().lower()
    if shell == "bash":
        return "bash -s"
    return "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command -"


def run_stdin_task(
    client: paramiko.SSHClient,
    command: str,
    script_text: str,
    timeout_seconds: int,
) -> int:
    transport = client.get_transport()
    if transport is None or not transport.is_active():
        raise RuntimeError("SSH transport is not active.")

    powershell_mode = command.strip().lower().startswith("powershell")
    payload = script_text or ""
    if payload and not payload.endswith("\n"):
        payload += "\n"
    remote_script_path = ""
    command_to_exec = command

    channel = transport.open_session()
    try:
        if powershell_mode:
            remote_script_path = f"C:/Windows/Temp/co-vm-task-{uuid.uuid4().hex}.ps1"
            sftp = client.open_sftp()
            try:
                with sftp.file(remote_script_path, "wb") as remote_file:
                    remote_file.write(payload.encode("utf-8", errors="replace"))
            finally:
                sftp.close()
            command_to_exec = (
                'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass '
                f'-File "{remote_script_path}"'
            )
            channel.exec_command(command_to_exec)
        else:
            channel.exec_command(command_to_exec)
            stdin_stream = channel.makefile_stdin("wb")
            try:
                stdin_stream.write(payload.encode("utf-8", errors="replace"))
                stdin_stream.flush()
            finally:
                stdin_stream.close()

        deadline = None
        if timeout_seconds > 0:
            deadline = time.monotonic() + timeout_seconds

        while True:
            while channel.recv_ready():
                chunk = channel.recv(65536)
                if chunk:
                    write_stdout(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
            while channel.recv_stderr_ready():
                chunk = channel.recv_stderr(65536)
                if chunk:
                    # Keep stderr visible in the same stream for easier parent-side parsing.
                    write_stdout("[stderr] " + sanitize_stream_text(chunk.decode("utf-8", errors="replace")))

            if channel.exit_status_ready():
                break

            if deadline is not None and time.monotonic() >= deadline:
                channel.close()
                return 124

            time.sleep(0.2)

        while channel.recv_ready():
            chunk = channel.recv(65536)
            if chunk:
                write_stdout(sanitize_stream_text(chunk.decode("utf-8", errors="replace")))
        while channel.recv_stderr_ready():
            chunk = channel.recv_stderr(65536)
            if chunk:
                write_stdout("[stderr] " + sanitize_stream_text(chunk.decode("utf-8", errors="replace")))

        return int(channel.recv_exit_status())
    finally:
        channel.close()
        if powershell_mode and remote_script_path:
            try:
                cleanup_channel = transport.open_session()
                try:
                    cleanup_command = (
                        'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass '
                        f'-Command "Remove-Item -LiteralPath ''{remote_script_path}'' -Force -ErrorAction SilentlyContinue"'
                    )
                    cleanup_channel.exec_command(cleanup_command)
                    cleanup_channel.recv_exit_status()
                finally:
                    cleanup_channel.close()
            except Exception:
                pass


def run_session(args: argparse.Namespace) -> int:
    session_command = resolve_session_command(args.shell)
    default_task_timeout = clamp_int(args.task_timeout, 5, 7200, 1800)
    reconnect_retries = clamp_int(args.reconnect_retries, 1, 3, 3)
    keepalive_seconds = clamp_int(args.keepalive_seconds, 5, 120, 15)

    client = reconnect_client(None, args)
    try:
        for raw_bytes in sys.stdin.buffer:
            if not raw_bytes:
                continue
            try:
                line = raw_bytes.decode("utf-8-sig", errors="replace").strip()
            except Exception:
                line = (str(raw_bytes) if raw_bytes is not None else "").strip()
            line = line.replace("\x00", "")
            if line.startswith("\ufeff"):
                line = line.lstrip("\ufeff")
            if not line:
                continue

            try:
                request = json.loads(line)
            except Exception as exc:
                write_stdout(f"CLAGNOS_SESSION_ERROR:invalid-json:{exc}\n")
                continue

            action = str(request.get("action", "")).strip().lower()
            if action == "close":
                write_stdout("CLAGNOS_SESSION_CLOSED\n")
                return 0

            if action != "run":
                write_stdout(f"CLAGNOS_SESSION_ERROR:unsupported-action:{action}\n")
                continue

            task_name = str(request.get("task", "task")).strip() or "task"
            script_text = str(request.get("script", ""))
            try:
                task_timeout = int(request.get("timeout", default_task_timeout))
            except Exception:
                task_timeout = default_task_timeout
            if task_timeout < 5:
                task_timeout = 5

            write_stdout(f"CLAGNOS_TASK_BEGIN:{task_name}\n")

            task_exit_code = 1
            last_exception = None
            for attempt in range(1, reconnect_retries + 1):
                try:
                    transport = client.get_transport()
                    if transport is None or not transport.is_active():
                        client = reconnect_client(client, args)
                        transport = client.get_transport()
                        if transport is not None:
                            transport.set_keepalive(keepalive_seconds)
                    task_exit_code = run_stdin_task(
                        client=client,
                        command=session_command,
                        script_text=script_text,
                        timeout_seconds=task_timeout,
                    )
                    last_exception = None
                    break
                except Exception as exc:
                    last_exception = exc
                    if attempt >= reconnect_retries:
                        break
                    write_stdout(
                        f"[stderr] CLAGNOS_SESSION_RECONNECT_RETRY:{task_name}:{attempt}/{reconnect_retries}:{exc}\n"
                    )
                    time.sleep(2)
                    client = reconnect_client(client, args)

            if last_exception is not None:
                write_stdout(f"[stderr] CLAGNOS_SESSION_TASK_ERROR:{task_name}:{last_exception}\n")
                task_exit_code = 1

            write_stdout(f"CLAGNOS_TASK_END:{task_name}:{task_exit_code}\n")

        return 0
    finally:
        client.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Portable SSH/SFTP client wrapper based on Paramiko.")
    subparsers = parser.add_subparsers(dest="action", required=True)

    def add_common(common_parser: argparse.ArgumentParser) -> None:
        common_parser.add_argument("--host", required=True, help="Remote host or FQDN")
        common_parser.add_argument("--port", type=int, default=22, help="Remote SSH port")
        common_parser.add_argument("--user", required=True, help="SSH username")
        common_parser.add_argument("--password", required=True, help="SSH password")
        common_parser.add_argument("--timeout", type=int, default=30, help="Connection timeout in seconds")
        common_parser.add_argument(
            "--reconnect-retries",
            type=int,
            default=3,
            help="Maximum reconnect retries when the SSH link drops (1-3)",
        )
        common_parser.add_argument(
            "--keepalive-seconds",
            type=int,
            default=15,
            help="SSH keepalive interval in seconds",
        )

    exec_parser = subparsers.add_parser("exec", help="Execute a remote command over SSH")
    add_common(exec_parser)
    exec_parser.add_argument("--command", required=True, help="Remote command to execute")
    exec_parser.add_argument("--stdin-file", help="Optional local file path streamed to the remote command over stdin")
    exec_parser.add_argument("--stdin-file-offset", type=int, default=0, help="Optional byte offset into --stdin-file")
    exec_parser.add_argument("--stdin-file-length", type=int, default=-1, help="Optional byte count from --stdin-file")

    copy_parser = subparsers.add_parser("copy", help="Copy local file to remote path over SFTP")
    add_common(copy_parser)
    copy_parser.add_argument("--local", required=True, help="Local file path")
    copy_parser.add_argument("--remote", required=True, help="Remote file path")

    fetch_parser = subparsers.add_parser("fetch", help="Copy remote file to local path over SFTP")
    add_common(fetch_parser)
    fetch_parser.add_argument("--remote", required=True, help="Remote file path")
    fetch_parser.add_argument("--local", required=True, help="Local file path")

    shell_parser = subparsers.add_parser("shell", help="Open an interactive remote shell over SSH")
    add_common(shell_parser)
    shell_parser.add_argument(
        "--shell",
        choices=("powershell", "cmd", "bash"),
        default="",
        help="Optional initial shell command to run after connection",
    )

    session_parser = subparsers.add_parser(
        "session",
        help="Open one persistent SSH connection and execute task scripts from stdin",
    )
    add_common(session_parser)
    session_parser.add_argument(
        "--shell",
        choices=("powershell", "bash"),
        default="powershell",
        help="Remote shell style used for stdin task execution",
    )
    session_parser.add_argument(
        "--task-timeout",
        type=int,
        default=1800,
        help="Default per-task timeout in seconds",
    )

    return parser.parse_args()


def main() -> int:
    configure_stdio()
    args = parse_args()
    if args.action == "exec":
        return run_exec(args)
    if args.action == "copy":
        return run_copy(args)
    if args.action == "fetch":
        return run_fetch(args)
    if args.action == "shell":
        return run_shell(args)
    if args.action == "session":
        return run_session(args)
    write_stderr(f"Unsupported action: {args.action}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
