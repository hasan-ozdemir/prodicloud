using System;
using System.IO;

public static class ClagnosTuiNetFixture
{
    public static int Main(string[] args)
    {
        string logPath = Environment.GetEnvironmentVariable("CLAGNOS_TUI_NET_LOG");
        if (!String.IsNullOrEmpty(logPath))
        {
            File.AppendAllText(logPath, String.Join(" ", args) + Environment.NewLine);
        }

        return 0;
    }
}
