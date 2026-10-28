using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public static class ProdicloudTuiAzFixture
{
    public static int Main(string[] args)
    {
        string systemRoot = Environment.GetEnvironmentVariable("SystemRoot");
        string powershellPath = Path.Combine(systemRoot, @"System32\WindowsPowerShell\v1.0\powershell.exe");
        string fixturePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "az-fixture.ps1");
        string arguments = String.Join("\0", args);
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powershellPath;
        startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + fixturePath + "\"";
        startInfo.UseShellExecute = false;
        startInfo.EnvironmentVariables["PRODICLOUD_TUI_AZ_ARGUMENTS_BASE64"] = Convert.ToBase64String(Encoding.UTF8.GetBytes(arguments));

        using (Process fixture = Process.Start(startInfo))
        {
            fixture.WaitForExit();
            return fixture.ExitCode;
        }
    }
}
