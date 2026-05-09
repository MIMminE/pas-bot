using System;
using System.Drawing;
using System.Linq;
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
        menu.Items.Add("config.toml 가져오기", null, async (_, _) => await ImportFileAsync("config.toml", "TOML files (*.toml)|*.toml|All files (*.*)|*.*", "--config-file"));
        menu.Items.Add("담당자 파일 가져오기", null, async (_, _) => await ImportFileAsync("담당자 파일", "JSON files (*.json)|*.json|All files (*.*)|*.*", "--assignees-file"));
        menu.Items.Add("담당자 목록 보기", null, async (_, _) => await RunAsync("담당자 목록", "settings", "assignees", "list"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("설정 폴더 열기", null, (_, _) => runner.OpenSupportDirectory());
        menu.Items.Add("마지막 실행 결과 보기", null, (_, _) => ShowResultWindow("마지막 실행 결과", runner.LastOutput));
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

        if (ShouldShowResult(args, result.Succeeded))
        {
            ShowResultWindow(result.Succeeded ? $"{label} 결과" : $"{label} 오류 상세", result.Output);
        }
    }

    private async Task ImportFileAsync(string label, string filter, string option)
    {
        using var dialog = new OpenFileDialog
        {
            Title = $"{label} 가져오기",
            Filter = filter,
            CheckFileExists = true,
            Multiselect = false
        };
        if (dialog.ShowDialog() == DialogResult.OK)
        {
            await RunAsync($"{label} 가져오기", "settings", "import", option, dialog.FileName);
        }
    }

    private static bool ShouldShowResult(string[] args, bool succeeded)
    {
        if (!succeeded)
        {
            return true;
        }
        if (args.Contains("--dry-run"))
        {
            return true;
        }
        return args.FirstOrDefault() is "status" or "settings";
    }

    private static void ShowResultWindow(string title, string output)
    {
        using var form = new Form
        {
            Text = title,
            Width = 820,
            Height = 560,
            StartPosition = FormStartPosition.CenterScreen
        };

        var textBox = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Both,
            WordWrap = false,
            Dock = DockStyle.Fill,
            Font = new Font(FontFamily.GenericMonospace, 10),
            Text = string.IsNullOrWhiteSpace(output) ? "출력 없음" : output
        };

        var copyButton = new Button
        {
            Text = "복사",
            Dock = DockStyle.Bottom,
            Height = 36
        };
        copyButton.Click += (_, _) => Clipboard.SetText(textBox.Text);

        form.Controls.Add(textBox);
        form.Controls.Add(copyButton);
        form.ShowDialog();
    }
}
