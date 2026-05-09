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

        menu.Items.Add("Slack 테스트 전송", null, async (_, _) => await RunAsync("Slack 테스트", "slack", "test"));
        menu.Items.Add("Jira 브리핑 전송", null, async (_, _) => await RunAsync("Jira 브리핑", "jira", "today", "--send-slack"));
        menu.Items.Add("Jira 브리핑 미리보기", null, async (_, _) => await RunAsync("Jira 미리보기", "jira", "today", "--dry-run"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Git 상태 전송", null, async (_, _) => await RunAsync("Git 상태", "repo", "status", "--send-slack"));
        menu.Items.Add("Git 상태 미리보기", null, async (_, _) => await RunAsync("Git 상태 미리보기", "repo", "status", "--dry-run"));
        menu.Items.Add("설정 진단 실행", null, async (_, _) => await RunAsync("설정 진단", "status", "doctor"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("설정 폴더 열기", null, (_, _) => runner.OpenSupportDirectory());
        menu.Items.Add("마지막 실행 결과 복사", null, (_, _) => runner.CopyLastOutputToClipboard());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => ExitThread());

        return menu;
    }

    private async Task RunAsync(string label, params string[] args)
    {
        notifyIcon.Text = "PAS - 실행 중";
        var result = await runner.RunAsync(args);
        notifyIcon.Text = "PAS";
        notifyIcon.ShowBalloonTip(
            4000,
            result.Succeeded ? $"PAS: {label} 성공" : $"PAS: {label} 실패",
            result.Summary,
            result.Succeeded ? ToolTipIcon.Info : ToolTipIcon.Error
        );
    }
}
