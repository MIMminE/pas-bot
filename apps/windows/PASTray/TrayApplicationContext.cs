using System;
using System.Drawing;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PASTray;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly PASRunner runner = new();
    private readonly NotifyIcon notifyIcon;

    public TrayApplicationContext()
    {
        notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "PAS",
            Visible = true,
            ContextMenuStrip = BuildMenu()
        };
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            notifyIcon.Visible = false;
            notifyIcon.Dispose();
        }
        base.Dispose(disposing);
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();

        menu.Items.Add("Send Slack Test", null, async (_, _) => await RunAsync("Slack test", "slack", "test"));
        menu.Items.Add("Send Jira Briefing", null, async (_, _) => await RunAsync("Jira briefing", "jira", "today", "--send-slack"));
        menu.Items.Add("Jira Briefing Dry Run", null, async (_, _) => await RunAsync("Jira dry-run", "jira", "today", "--dry-run"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Send Git Status", null, async (_, _) => await RunAsync("Git status", "repo", "status", "--send-slack"));
        menu.Items.Add("Git Status Dry Run", null, async (_, _) => await RunAsync("Git status dry-run", "repo", "status", "--dry-run"));
        menu.Items.Add("Run Setup Doctor", null, async (_, _) => await RunAsync("Setup doctor", "status", "doctor"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open Settings Folder", null, (_, _) => runner.OpenSupportDirectory());
        menu.Items.Add("Copy Last Output", null, (_, _) => runner.CopyLastOutputToClipboard());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());

        return menu;
    }

    private async Task RunAsync(string label, params string[] args)
    {
        notifyIcon.Text = "PAS - Running";
        var result = await runner.RunAsync(args);
        notifyIcon.Text = "PAS";
        notifyIcon.ShowBalloonTip(
            4000,
            result.Succeeded ? $"PAS: {label} succeeded" : $"PAS: {label} failed",
            result.Summary,
            result.Succeeded ? ToolTipIcon.Info : ToolTipIcon.Error
        );
    }
}
