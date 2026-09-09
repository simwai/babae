using System;
using System.Diagnostics;
using System.IO;

internal static class Program
{
    private static int Main(string[] args)
    {
        var scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "babae.ps1");
        var arguments = "-NoProfile -File " + Quote(scriptPath);

        foreach (var argument in args)
        {
            arguments += " " + Quote(argument);
        }

        using (var process = Process.Start(new ProcessStartInfo
        {
            FileName = "pwsh",
            Arguments = arguments,
            UseShellExecute = false
        }))
        {
            if (process == null)
            {
                return 1;
            }

            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
