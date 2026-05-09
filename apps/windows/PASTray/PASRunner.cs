using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PASTray;

internal sealed class PASRunner
{
    private string lastOutput = "";

    public async Task<PASResult> RunAsync(params string[] args)
    {
        PrepareSupportFiles();

        var startInfo = new ProcessStartInfo
        {
            FileName = PasExecutablePath(),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        startInfo.ArgumentList.Add("--config");
        startInfo.ArgumentList.Add(ConfigPath());
        startInfo.ArgumentList.Add("--env");
        startInfo.ArgumentList.Add(EnvPath());
        foreach (var arg in args)
        {
            startInfo.ArgumentList.Add(arg);
        }

        try
        {
            using var process = Process.Start(startInfo);
            if (process == null)
            {
                return Fail("Failed to start pas.exe");
            }

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            var output = await outputTask;
            var error = await errorTask;
            lastOutput = string.Join(Environment.NewLine, new[] { output, error }.Where(value => !string.IsNullOrWhiteSpace(value)));
            var summary = string.IsNullOrWhiteSpace(lastOutput) ? "No output" : Truncate(lastOutput.Trim(), 180);
            return new PASResult(process.ExitCode == 0, lastOutput, summary);
        }
        catch (Exception ex)
        {
            return Fail(ex.Message);
        }
    }

    public void OpenSupportDirectory()
    {
        Directory.CreateDirectory(SupportDirectory());
        Process.Start(new ProcessStartInfo
        {
            FileName = SupportDirectory(),
            UseShellExecute = true
        });
    }

    public void CopyLastOutputToClipboard()
    {
        if (!string.IsNullOrWhiteSpace(lastOutput))
        {
            Clipboard.SetText(lastOutput);
        }
    }

    private PASResult Fail(string message)
    {
        lastOutput = message;
        return new PASResult(false, message, message);
    }

    private void PrepareSupportFiles()
    {
        Directory.CreateDirectory(SupportDirectory());
        CopyIfMissing(Path.Combine(AppContext.BaseDirectory, "config.example.toml"), ConfigPath());
        CopyIfMissing(Path.Combine(AppContext.BaseDirectory, ".env.example"), EnvPath());
    }

    private static void CopyIfMissing(string source, string destination)
    {
        if (!File.Exists(destination) && File.Exists(source))
        {
            File.Copy(source, destination);
        }
    }

    private static string PasExecutablePath()
    {
        var bundled = Path.Combine(AppContext.BaseDirectory, "bin", "pas.exe");
        return File.Exists(bundled) ? bundled : "pas.exe";
    }

    private static string SupportDirectory()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "PAS");
    }

    private static string ConfigPath() => Path.Combine(SupportDirectory(), "config.toml");

    private static string EnvPath() => Path.Combine(SupportDirectory(), ".env");

    private static string Truncate(string value, int length)
    {
        return value.Length <= length ? value : value[..(length - 3)] + "...";
    }
}

internal sealed record PASResult(bool Succeeded, string Output, string Summary);
