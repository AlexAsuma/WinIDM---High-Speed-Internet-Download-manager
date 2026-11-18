@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Installing & Launching WinIDM...
echo Building and registering WinIDM native Windows application...

taskkill /F /IM WinIDM.exe >nul 2>&1

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\WinIDM"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
set "EXE_FILE=%INSTALL_DIR%\WinIDM.exe"
set "CS_FILE=%TEMP%\WinIDM_AppSource.cs"
set "BAT_SELF=%~f0"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$lines = Get-Content -LiteralPath $env:BAT_SELF -Encoding UTF8; " ^
  "$idx = [Array]::IndexOf($lines, '###CSHARP_SOURCE_START###'); " ^
  "$code = ($lines[($idx + 1)..($lines.Length - 1)]) -join [Environment]::NewLine; " ^
  "Set-Content -LiteralPath $env:CS_FILE -Value $code -Encoding UTF8"

set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

if not exist "%CSC%" (
    echo [ERROR] Microsoft .NET Framework 4.x compiler was not found on this PC.
    pause
    exit /b 1
)

"%CSC%" /nologo /target:winexe /optimize+ /out:"%EXE_FILE%" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll /r:System.IO.Compression.FileSystem.dll "%CS_FILE%"
del /f /q "%CS_FILE%" >nul 2>&1

if not exist "%EXE_FILE%" (
    echo [ERROR] Could not build WinIDM.exe.
    pause
    exit /b 1
)

start "" "%EXE_FILE%" --first-run
exit /b 0

###CSHARP_SOURCE_START###
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WinIDMApp
{
    public class BufferedListView : ListView
    {
        public BufferedListView()
        {
            this.DoubleBuffered = true;
            this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }
    }

    public class BufferedPanel : Panel
    {
        public BufferedPanel()
        {
            this.DoubleBuffered = true;
            this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }
    }

    public static class IdmIconFactory
    {
        public static Bitmap CreateToolbarIcon(string kind, int size)
        {
            Bitmap bmp = new Bitmap(size, size);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.Transparent);
                float s = size / 32.0f;

                if (kind == "add")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(74, 222, 128), Color.FromArgb(22, 163, 74), 45f))
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    using (Pen plus = new Pen(Color.White, 3.6f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                    {
                        g.DrawLine(plus, 16 * s, 9 * s, 16 * s, 23 * s);
                        g.DrawLine(plus, 9 * s, 16 * s, 23 * s, 16 * s);
                    }
                }
                else if (kind == "resume")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(52, 211, 153), Color.FromArgb(5, 150, 105), 45f))
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    g.FillPolygon(Brushes.White, new[] {
                        new PointF(12.5f * s, 9.5f * s), new PointF(23.0f * s, 16.0f * s), new PointF(12.5f * s, 22.5f * s)
                    });
                }
                else if (kind == "pause")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(251, 191, 36), Color.FromArgb(217, 119, 6), 45f))
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    g.FillRectangle(Brushes.White, 11.2f * s, 10 * s, 3.4f * s, 12 * s);
                    g.FillRectangle(Brushes.White, 17.4f * s, 10 * s, 3.4f * s, 12 * s);
                }
                else if (kind == "stopall")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(248, 113, 113), Color.FromArgb(220, 38, 38), 45f))
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    g.FillRectangle(Brushes.White, 10.5f * s, 10.5f * s, 11 * s, 11 * s);
                }
                else if (kind == "delete")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(4, 4, size - 8, size - 8),
                        Color.FromArgb(239, 68, 68), Color.FromArgb(185, 28, 28), 90f))
                        g.FillRectangle(br, 8 * s, 9 * s, 16 * s, 18 * s);
                    using (Pen lid = new Pen(Color.FromArgb(153, 27, 27), 2.4f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                    {
                        g.DrawLine(lid, 6 * s, 7 * s, 26 * s, 7 * s);
                        g.DrawLine(lid, 13 * s, 4.5f * s, 19 * s, 4.5f * s);
                    }
                    using (Pen lines = new Pen(Color.White, 1.8f * s))
                    {
                        g.DrawLine(lines, 12 * s, 12 * s, 12 * s, 24 * s);
                        g.DrawLine(lines, 16 * s, 12 * s, 16 * s, 24 * s);
                        g.DrawLine(lines, 20 * s, 12 * s, 20 * s, 24 * s);
                    }
                }
                else if (kind == "deldone")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(96, 165, 250), Color.FromArgb(37, 99, 235), 45f))
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    using (Pen chk = new Pen(Color.White, 3.0f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                        g.DrawLines(chk, new[] { new PointF(9.5f * s, 16.5f * s), new PointF(14.0f * s, 21.0f * s), new PointF(22.5f * s, 11.5f * s) });
                }
                else if (kind == "options")
                {
                    using (Pen gear = new Pen(Color.FromArgb(71, 85, 105), 4.2f * s))
                        g.DrawEllipse(gear, 8 * s, 8 * s, 16 * s, 16 * s);
                    using (Brush tooth = new SolidBrush(Color.FromArgb(51, 65, 85)))
                    {
                        for (int i = 0; i < 8; i++)
                        {
                            GraphicsState st = g.Save();
                            g.TranslateTransform(16 * s, 16 * s);
                            g.RotateTransform(i * 45f);
                            g.FillRectangle(tooth, -2.2f * s, -13.5f * s, 4.4f * s, 4.5f * s);
                            g.Restore(st);
                        }
                    }
                }
                else if (kind == "scheduler")
                {
                    g.FillEllipse(Brushes.White, 4 * s, 4 * s, 24 * s, 24 * s);
                    using (Pen rim = new Pen(Color.FromArgb(37, 99, 235), 2.6f * s))
                        g.DrawEllipse(rim, 4 * s, 4 * s, 24 * s, 24 * s);
                    using (Pen hand = new Pen(Color.FromArgb(30, 41, 59), 2.4f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                    {
                        g.DrawLine(hand, 16 * s, 16 * s, 16 * s, 9 * s);
                        g.DrawLine(hand, 16 * s, 16 * s, 21 * s, 18 * s);
                    }
                }
                else if (kind == "grabber")
                {
                    using (LinearGradientBrush globe = new LinearGradientBrush(new Rectangle(3, 3, size - 6, size - 6),
                        Color.FromArgb(56, 189, 248), Color.FromArgb(2, 132, 199), 45f))
                        g.FillEllipse(globe, 4 * s, 4 * s, 24 * s, 24 * s);
                    using (Pen grid = new Pen(Color.FromArgb(210, 255, 255, 255), 1.4f * s))
                    {
                        g.DrawEllipse(grid, 10 * s, 4 * s, 12 * s, 24 * s);
                        g.DrawLine(grid, 4 * s, 16 * s, 28 * s, 16 * s);
                    }
                }
                else if (kind == "batch")
                {
                    using (Brush backDoc = new SolidBrush(Color.FromArgb(148, 163, 184)))
                        g.FillRectangle(backDoc, 6 * s, 4 * s, 15 * s, 19 * s);
                    using (Brush frontDoc = new SolidBrush(Color.FromArgb(59, 130, 246)))
                        g.FillRectangle(frontDoc, 11 * s, 8 * s, 15 * s, 20 * s);
                }
                else if (kind == "speed")
                {
                    using (Pen arc = new Pen(Color.FromArgb(234, 88, 12), 3.4f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                        g.DrawArc(arc, 4 * s, 6 * s, 24 * s, 24 * s, 180, 180);
                    using (Pen needle = new Pen(Color.FromArgb(30, 41, 59), 2.5f * s) { EndCap = LineCap.Round })
                        g.DrawLine(needle, 16 * s, 22 * s, 23 * s, 12 * s);
                }
                else if (kind == "browser")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(3, 3, size - 6, size - 6),
                        Color.FromArgb(129, 140, 248), Color.FromArgb(79, 70, 229), 45f))
                        g.FillRectangle(br, 4 * s, 5 * s, 24 * s, 22 * s);
                    using (Pen arrow = new Pen(Color.White, 2.5f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                    {
                        g.DrawLine(arrow, 16 * s, 12 * s, 16 * s, 23 * s);
                        g.DrawLine(arrow, 12 * s, 19 * s, 16 * s, 23 * s);
                        g.DrawLine(arrow, 20 * s, 19 * s, 16 * s, 23 * s);
                    }
                }
            }
            return bmp;
        }

        public static Bitmap CreateCategoryIcon(string category)
        {
            Bitmap bmp = new Bitmap(16, 16);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                string cat = (category ?? "").ToLowerInvariant();
                if (cat == "video")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(225, 29, 72))) g.FillRectangle(b, 1, 2, 14, 12);
                    g.FillPolygon(Brushes.White, new[] { new Point(6, 5), new Point(12, 8), new Point(6, 11) });
                }
                else if (cat == "music")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(147, 51, 234))) g.FillEllipse(b, 1, 1, 14, 14);
                    g.FillEllipse(Brushes.White, 4, 9, 4, 3);
                    g.FillRectangle(Brushes.White, 7, 4, 2, 7);
                }
                else if (cat == "compressed")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(217, 119, 6))) g.FillRectangle(b, 2, 1, 12, 14);
                    g.FillRectangle(Brushes.White, 7, 2, 2, 12);
                }
                else if (cat == "programs")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(37, 99, 235))) g.FillRectangle(b, 1, 2, 14, 12);
                    g.FillRectangle(Brushes.White, 4, 7, 8, 4);
                }
                else if (cat == "documents")
                {
                    g.FillRectangle(Brushes.White, 2, 1, 12, 14);
                    using (Pen p = new Pen(Color.FromArgb(2, 132, 199), 1.3f)) g.DrawRectangle(p, 2, 1, 11, 13);
                }
                else if (cat == "finished" || cat == "completed")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(22, 163, 74))) g.FillEllipse(b, 1, 1, 14, 14);
                    using (Pen p = new Pen(Color.White, 2f)) g.DrawLines(p, new[] { new Point(4, 8), new Point(7, 11), new Point(12, 5) });
                }
                else if (cat == "unfinished")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(234, 88, 12))) g.FillEllipse(b, 1, 1, 14, 14);
                    using (Pen p = new Pen(Color.White, 2f)) { g.DrawLine(p, 8, 4, 8, 10); g.DrawLine(p, 5, 8, 8, 11); g.DrawLine(p, 11, 8, 8, 11); }
                }
                else
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(250, 204, 21))) g.FillRectangle(b, 1, 4, 14, 10);
                }
            }
            return bmp;
        }
    }

    public class BandwidthLimiter
    {
        private readonly object _lock = new object();
        private volatile bool _hasLimit = false;
        private double _limitBps = 0.0;
        private double _tokens = 0.0;
        private DateTime _lastRefill = DateTime.UtcNow;

        public void SetLimitKbps(double kbps)
        {
            lock (_lock)
            {
                if (kbps > 0.0)
                {
                    _limitBps = kbps * 1024.0;
                    _tokens = _limitBps;
                    _lastRefill = DateTime.UtcNow;
                    _hasLimit = true;
                }
                else
                {
                    _limitBps = 0.0;
                    _tokens = 0.0;
                    _hasLimit = false;
                }
            }
        }

        public double GetLimitKbps()
        {
            lock (_lock) { return _limitBps / 1024.0; }
        }

        public void Consume(int bytes)
        {
            if (!_hasLimit || bytes <= 0) return;
            while (true)
            {
                int sleepMs = 0;
                lock (_lock)
                {
                    if (!_hasLimit || _limitBps <= 0.0) return;
                    DateTime now = DateTime.UtcNow;
                    double elapsed = (now - _lastRefill).TotalSeconds;
                    _lastRefill = now;
                    _tokens = Math.Min(_limitBps, _tokens + elapsed * _limitBps);

                    if (_tokens >= bytes)
                    {
                        _tokens -= bytes;
                        return;
                    }
                    double deficit = bytes - _tokens;
                    double waitSec = Math.Min(0.25, deficit / _limitBps);
                    sleepMs = Math.Max(1, (int)(waitSec * 1000.0));
                }
                Thread.Sleep(sleepMs);
            }
        }
    }

    public class DownloadSegment
    {
        public int Index;
        public long Start;
        public long End;
        public long Current;
        public long Downloaded;
        public bool Done;
        public bool Active;
        public string SegmentUrl;
    }

    public enum DownloadState
    {
        Queued,
        Connecting,
        Downloading,
        Finalizing,
        Paused,
        Completed,
        Error
    }

    public class DownloadTask
    {
        private static readonly HttpClient SharedHttpClient = CreateHighSpeedHttpClient();

        private static HttpClient CreateHighSpeedHttpClient()
        {
            ServicePointManager.DefaultConnectionLimit = 512;
            ServicePointManager.Expect100Continue = false;
            ServicePointManager.UseNagleAlgorithm = false;
            ServicePointManager.EnableDnsRoundRobin = true;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288;

            HttpClientHandler handler = new HttpClientHandler
            {
                UseProxy = false,
                AllowAutoRedirect = true,
                MaxAutomaticRedirections = 12,
                AutomaticDecompression = DecompressionMethods.None,
                MaxConnectionsPerServer = 64,
                UseCookies = false
            };

            HttpClient client = new HttpClient(handler, true) { Timeout = TimeSpan.FromMinutes(30) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) WinIDM/6.43");
            client.DefaultRequestHeaders.Accept.ParseAdd("*/*");
            client.DefaultRequestHeaders.ConnectionClose = false;
            return client;
        }

        public string Id;
        public string Url;
        public string FileName;
        public string Category;
        public string SaveDir;
        public int NumThreads;
        public bool ComputeSha256;
        public string ExpectedSha256 = "";
        public bool ChecksumMismatch = false;
        public bool AutoExtractZip = false;
        public string StreamFormat = "best";
        public Dictionary<string, string> CustomHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public long TotalSize = -1;
        public bool SupportsRanges = false;
        public bool IsHls = false;
        public bool IsStreamPage = false;
        public bool DirectWrite = false;
        public volatile DownloadState Status = DownloadState.Queued;
        public string ErrorMessage = "";
        public string Sha256Hash = "";

        public readonly object SyncLock = new object();
        public List<DownloadSegment> Segments = new List<DownloadSegment>();

        public double StreamPercent = 0.0;
        public long StreamDownloadedBytes = 0;
        public double SpeedBps = 0.0;
        public double EtaSeconds = -1.0;

        private volatile bool _pauseFlag = false;
        private volatile bool _cancelFlag = false;
        private volatile CancellationTokenSource _cts = null;
        private volatile Process _activeExtractorProc = null;

        private long _lastSampleTicks = 0;
        private long _lastSampleBytes = 0;

        public static bool IsVideoPageUrl(string rawUrl)
        {
            if (string.IsNullOrWhiteSpace(rawUrl)) return false;
            return Regex.IsMatch(rawUrl.Trim(),
                @"^https?://(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch|shorts/|live/|embed/)|youtu\.be/|vimeo\.com/\d+|dailymotion\.com/video/|twitch\.tv/videos/|tiktok\.com/@[^/]+/video/|(?:x|twitter)\.com/[^/]+/status/|facebook\.com/.+/videos/|instagram\.com/(?:p|reel|tv)/)",
                RegexOptions.IgnoreCase);
        }

        public string FullFilePath { get { return Path.Combine(SaveDir, FileName); } }
        public string TempDirPath { get { return Path.Combine(AppPaths.BaseDownloadDir, ".tmp", Id); } }

        public long GetDownloadedBytes()
        {
            if (IsStreamPage) return StreamDownloadedBytes;
            lock (SyncLock)
            {
                long sum = 0;
                for (int i = 0; i < Segments.Count; i++)
                {
                    DownloadSegment s = Segments[i];
                    if (!IsHls && s.Start >= 0) sum += Math.Max(0L, s.Current - s.Start);
                    else sum += s.Downloaded;
                }
                return sum;
            }
        }

        public double GetProgressPercent()
        {
            if (Status == DownloadState.Completed) return 100.0;
            if (IsStreamPage) return Math.Min(100.0, Math.Max(0.0, StreamPercent));
            if (IsHls)
            {
                lock (SyncLock)
                {
                    if (Segments.Count == 0) return 0.0;
                    int done = Segments.Count(s => s.Done);
                    return (100.0 * done) / Segments.Count;
                }
            }
            if (TotalSize <= 0) return 0.0;
            return Math.Min(100.0, (100.0 * GetDownloadedBytes()) / TotalSize);
        }

        public void UpdateMetrics()
        {
            if (Status != DownloadState.Downloading)
            {
                SpeedBps = 0.0;
                EtaSeconds = -1.0;
                _lastSampleTicks = 0;
                return;
            }
            if (IsStreamPage) return;

            long nowTicks = Stopwatch.GetTimestamp();
            long curBytes = GetDownloadedBytes();

            if (_lastSampleTicks == 0)
            {
                _lastSampleTicks = nowTicks;
                _lastSampleBytes = curBytes;
                return;
            }

            double dt = (double)(nowTicks - _lastSampleTicks) / Stopwatch.Frequency;
            if (dt >= 0.25)
            {
                long delta = Math.Max(0L, curBytes - _lastSampleBytes);
                double instant = delta / dt;
                SpeedBps = (SpeedBps <= 0.0) ? instant : (0.35 * instant + 0.65 * SpeedBps);
                _lastSampleTicks = nowTicks;
                _lastSampleBytes = curBytes;
            }

            if (TotalSize > 0 && SpeedBps > 1.0)
                EtaSeconds = Math.Max(0.0, (TotalSize - curBytes) / SpeedBps);
            else
                EtaSeconds = -1.0;
        }

        public void Start(BandwidthLimiter limiter, Action onStateChanged)
        {
            if (Status == DownloadState.Downloading || Status == DownloadState.Connecting) return;
            _pauseFlag = false;
            _cancelFlag = false;
            ErrorMessage = "";
            ChecksumMismatch = false;
            Status = DownloadState.Connecting;
            _lastSampleTicks = 0;
            _lastSampleBytes = GetDownloadedBytes();
            _cts = new CancellationTokenSource();
            Task.Run(() => RunCoordinator(limiter, onStateChanged));
        }

        public void Pause()
        {
            _pauseFlag = true;
            try { if (_cts != null) _cts.Cancel(); } catch { }
            Process p = _activeExtractorProc;
            if (p != null) { try { if (!p.HasExited) p.Kill(); } catch { } }
            if (Status == DownloadState.Downloading || Status == DownloadState.Connecting || Status == DownloadState.Queued)
            {
                Status = DownloadState.Paused;
                SpeedBps = 0.0;
            }
        }

        public void Cancel()
        {
            _cancelFlag = true;
            _pauseFlag = true;
            try { if (_cts != null) _cts.Cancel(); } catch { }
            Process p = _activeExtractorProc;
            if (p != null) { try { if (!p.HasExited) p.Kill(); } catch { } }
        }

        private HttpRequestMessage BuildRequest(string targetUrl, long rangeStart, long rangeEnd)
        {
            HttpRequestMessage req = new HttpRequestMessage(HttpMethod.Get, targetUrl);
            req.Version = new Version(2, 0);
            foreach (var kv in CustomHeaders) req.Headers.TryAddWithoutValidation(kv.Key, kv.Value);
            if (rangeStart >= 0)
            {
                req.Headers.Range = (rangeEnd >= rangeStart) ? new RangeHeaderValue(rangeStart, rangeEnd) : new RangeHeaderValue(rangeStart, null);
            }
            return req;
        }

        private static string ExtractFileName(HttpResponseMessage resp, string finalUrl)
        {
            if (resp.Content != null && resp.Content.Headers.ContentDisposition != null)
            {
                string dispName = resp.Content.Headers.ContentDisposition.FileNameStar ?? resp.Content.Headers.ContentDisposition.FileName;
                if (!string.IsNullOrWhiteSpace(dispName))
                {
                    string clean = AppPaths.SanitizeFileName(Uri.UnescapeDataString(dispName.Trim().Trim('"')));
                    if (!string.IsNullOrEmpty(clean) && clean != "download.bin") return clean;
                }
            }
            try
            {
                Uri uri = new Uri(finalUrl);
                string seg = Path.GetFileName(Uri.UnescapeDataString(uri.AbsolutePath));
                if (!string.IsNullOrEmpty(seg)) return AppPaths.SanitizeFileName(seg);
            }
            catch { }
            return "download.bin";
        }

        private bool ProbeServer()
        {
            try
            {
                HttpResponseMessage resp = null;
                using (HttpRequestMessage req = BuildRequest(Url, 0, 0))
                {
                    resp = SharedHttpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, _cts.Token).GetAwaiter().GetResult();
                }
                if ((int)resp.StatusCode == 416)
                {
                    resp.Dispose();
                    using (HttpRequestMessage retryReq = BuildRequest(Url, -1, -1))
                    {
                        resp = SharedHttpClient.SendAsync(retryReq, HttpCompletionOption.ResponseHeadersRead, _cts.Token).GetAwaiter().GetResult();
                    }
                }
                using (resp)
                {
                    resp.EnsureSuccessStatusCode();
                    string finalUrl = (resp.RequestMessage != null && resp.RequestMessage.RequestUri != null) ? resp.RequestMessage.RequestUri.ToString() : Url;
                    if (string.IsNullOrEmpty(FileName)) FileName = ExtractFileName(resp, finalUrl);

                    if (finalUrl.ToLowerInvariant().Contains(".m3u8") || FileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
                        return ProbeHlsManifest();

                    if (resp.StatusCode == HttpStatusCode.PartialContent && resp.Content.Headers.ContentRange != null && resp.Content.Headers.ContentRange.Length.HasValue)
                    {
                        SupportsRanges = true;
                        TotalSize = resp.Content.Headers.ContentRange.Length.Value;
                    }
                    else
                    {
                        SupportsRanges = false;
                        if (resp.Content.Headers.ContentLength.HasValue) TotalSize = resp.Content.Headers.ContentLength.Value;
                    }
                }

                if (string.IsNullOrEmpty(Category)) Category = AppPaths.DetectCategory(FileName);
                if (string.IsNullOrEmpty(SaveDir)) SaveDir = Path.Combine(AppPaths.BaseDownloadDir, Category);
                return true;
            }
            catch (Exception ex) { ErrorMessage = ex.Message; return false; }
        }

        private string DownloadTextSync(string targetUrl)
        {
            using (HttpRequestMessage req = BuildRequest(targetUrl, -1, -1))
            using (HttpResponseMessage resp = SharedHttpClient.SendAsync(req, HttpCompletionOption.ResponseContentRead, _cts.Token).GetAwaiter().GetResult())
            {
                resp.EnsureSuccessStatusCode();
                return resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            }
        }

        private bool ProbeHlsManifest()
        {
            try
            {
                IsHls = true;
                SupportsRanges = false;
                DirectWrite = false;
                string playlistUrl = Url;
                string m3u8 = DownloadTextSync(playlistUrl);

                if (m3u8.Contains("#EXT-X-STREAM-INF"))
                {
                    string[] lines = m3u8.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    long bestBw = -1;
                    string bestUri = null;
                    long curBw = 0;
                    foreach (string raw in lines)
                    {
                        string line = raw.Trim();
                        if (line.StartsWith("#EXT-X-STREAM-INF"))
                        {
                            Match m = Regex.Match(line, @"BANDWIDTH=(\d+)");
                            curBw = m.Success ? long.Parse(m.Groups[1].Value) : 0;
                        }
                        else if (!line.StartsWith("#") && curBw >= bestBw) { bestBw = curBw; bestUri = line; }
                    }
                    if (!string.IsNullOrEmpty(bestUri))
                    {
                        playlistUrl = new Uri(new Uri(playlistUrl), bestUri).ToString();
                        m3u8 = DownloadTextSync(playlistUrl);
                    }
                }

                List<string> segUrls = new List<string>();
                string initMapUrl = null;
                bool encrypted = false;
                foreach (string raw in m3u8.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string line = raw.Trim();
                    if (line.StartsWith("#EXT-X-KEY:")) { if (!line.Contains("METHOD=NONE")) encrypted = true; continue; }
                    if (line.StartsWith("#EXT-X-MAP:"))
                    {
                        Match m = Regex.Match(line, @"URI=""([^""]+)""");
                        if (m.Success) initMapUrl = new Uri(new Uri(playlistUrl), m.Groups[1].Value).ToString();
                        continue;
                    }
                    if (line.StartsWith("#")) continue;
                    segUrls.Add(new Uri(new Uri(playlistUrl), line).ToString());
                }

                if (encrypted) { ErrorMessage = "Stream is DRM/AES encrypted."; return false; }
                if (segUrls.Count == 0) { ErrorMessage = "No segments found in stream."; return false; }

                bool isFmp4 = !string.IsNullOrEmpty(initMapUrl) || segUrls[0].ToLowerInvariant().Contains(".m4s");
                if (isFmp4 && !string.IsNullOrEmpty(initMapUrl)) segUrls.Insert(0, initMapUrl);

                if (FileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
                    FileName = Path.ChangeExtension(FileName, isFmp4 ? ".mp4" : ".ts");
                Category = "Video";
                if (string.IsNullOrEmpty(SaveDir)) SaveDir = Path.Combine(AppPaths.BaseDownloadDir, Category);

                lock (SyncLock)
                {
                    Segments.Clear();
                    for (int i = 0; i < segUrls.Count; i++)
                    {
                        Segments.Add(new DownloadSegment { Index = i, Start = -1, End = -1, SegmentUrl = segUrls[i] });
                    }
                }
                return true;
            }
            catch (Exception ex) { ErrorMessage = "HLS Error: " + ex.Message; return false; }
        }

        private bool PrepareDirectFile()
        {
            string target = FullFilePath;
            if (File.Exists(target))
            {
                string dir = Path.GetDirectoryName(target);
                string stem = Path.GetFileNameWithoutExtension(target);
                string ext = Path.GetExtension(target);
                int counter = 1;
                while (File.Exists(Path.Combine(dir, string.Format("{0} ({1}){2}", stem, counter, ext)))) counter++;
                FileName = string.Format("{0} ({1}){2}", stem, counter, ext);
                target = FullFilePath;
            }
            try
            {
                using (new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.ReadWrite)) { }
                return true;
            }
            catch (Exception ex) { ErrorMessage = "Disk error: " + ex.Message; return false; }
        }

        private bool InitializeSegments()
        {
            lock (SyncLock)
            {
                if (Segments.Count > 0) return true;
                if (SupportsRanges && TotalSize > 131072 && NumThreads > 1)
                {
                    DirectWrite = true;
                    if (!PrepareDirectFile()) return false;
                    int effectiveThreads = (int)Math.Min((long)NumThreads, Math.Max(1L, TotalSize / 131072L));
                    long chunk = TotalSize / effectiveThreads;
                    for (int i = 0; i < effectiveThreads; i++)
                    {
                        long st = i * chunk;
                        long en = (i == effectiveThreads - 1) ? (TotalSize - 1) : ((i + 1) * chunk - 1);
                        Segments.Add(new DownloadSegment { Index = i, Start = st, End = en, Current = st });
                    }
                }
                else
                {
                    SupportsRanges = false;
                    DirectWrite = false;
                    Segments.Add(new DownloadSegment { Index = 0, Start = 0, End = (TotalSize > 0) ? (TotalSize - 1) : -1, Current = 0 });
                }
                return true;
            }
        }

        private int StealWorkIndex()
        {
            if (!DirectWrite || IsHls) return -1;
            lock (SyncLock)
            {
                int bestIdx = -1;
                long bestRem = 0;
                for (int i = 0; i < Segments.Count; i++)
                {
                    DownloadSegment s = Segments[i];
                    if (!s.Done && s.End >= s.Current)
                    {
                        long rem = s.End - s.Current + 1;
                        if (rem > bestRem) { bestRem = rem; bestIdx = i; }
                    }
                }
                if (bestIdx < 0 || bestRem < 131072) return -1;

                long mid = Segments[bestIdx].Current + (bestRem / 2);
                long oldEnd = Segments[bestIdx].End;
                Segments[bestIdx].End = mid - 1;

                DownloadSegment stolen = new DownloadSegment { Index = Segments.Count, Start = mid, End = oldEnd, Current = mid, Active = true };
                Segments.Add(stolen);
                return stolen.Index;
            }
        }

        private async Task DownloadSegmentWorkerAsync(int segIdx, BandwidthLimiter limiter)
        {
            string targetUrl;
            lock (SyncLock) { targetUrl = string.IsNullOrEmpty(Segments[segIdx].SegmentUrl) ? Url : Segments[segIdx].SegmentUrl; }

            const int maxRetries = 6;
            for (int attempt = 0; attempt < maxRetries; attempt++)
            {
                if (_pauseFlag || _cancelFlag) return;

                if (DirectWrite && !IsHls)
                {
                    long cur, end;
                    lock (SyncLock)
                    {
                        cur = Segments[segIdx].Current;
                        end = Segments[segIdx].End;
                        if (cur > end) { Segments[segIdx].Done = true; return; }
                    }

                    try
                    {
                        using (HttpRequestMessage req = BuildRequest(targetUrl, cur, end))
                        using (HttpResponseMessage resp = await SharedHttpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, _cts.Token).ConfigureAwait(false))
                        {
                            if (cur > 0 && resp.StatusCode != HttpStatusCode.PartialContent) throw new IOException("Server ignored byte-range.");
                            resp.EnsureSuccessStatusCode();

                            byte[] netBuf = new byte[131072];
                            byte[] writeBuf = new byte[524288];
                            int writeFill = 0;
                            long writeOffset = cur;

                            using (Stream netStream = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                            using (FileStream localFs = new FileStream(FullFilePath, FileMode.OpenOrCreate, FileAccess.Write, FileShare.ReadWrite, 524288, FileOptions.RandomAccess))
                            {
                                while (!_pauseFlag && !_cancelFlag)
                                {
                                    long rem;
                                    lock (SyncLock) { rem = Segments[segIdx].End - Segments[segIdx].Current + 1; }
                                    if (rem <= 0) break;

                                    int toRead = (int)Math.Min(netBuf.Length, rem);
                                    int read = await netStream.ReadAsync(netBuf, 0, toRead, _cts.Token).ConfigureAwait(false);
                                    if (read <= 0) break;

                                    limiter.Consume(read);
                                    Buffer.BlockCopy(netBuf, 0, writeBuf, writeFill, read);
                                    writeFill += read;
                                    lock (SyncLock) { Segments[segIdx].Current += read; }

                                    if (writeFill >= writeBuf.Length - netBuf.Length)
                                    {
                                        localFs.Seek(writeOffset, SeekOrigin.Begin);
                                        localFs.Write(writeBuf, 0, writeFill);
                                        writeOffset += writeFill;
                                        writeFill = 0;
                                    }
                                }
                                if (writeFill > 0)
                                {
                                    localFs.Seek(writeOffset, SeekOrigin.Begin);
                                    localFs.Write(writeBuf, 0, writeFill);
                                }
                            }
                        }

                        lock (SyncLock)
                        {
                            if (Segments[segIdx].Current > Segments[segIdx].End) { Segments[segIdx].Done = true; return; }
                        }
                        if (_pauseFlag || _cancelFlag) return;
                    }
                    catch (Exception ex)
                    {
                        if (_pauseFlag || _cancelFlag) return;
                        if (attempt == maxRetries - 1) { Status = DownloadState.Error; ErrorMessage = ex.Message; return; }
                        await Task.Delay(300 * (1 << Math.Min(attempt, 4))).ConfigureAwait(false);
                    }
                }
                else
                {
                    string partPath = Path.Combine(TempDirPath, string.Format("part_{0:D5}.tmp", segIdx));
                    try
                    {
                        lock (SyncLock) { Segments[segIdx].Downloaded = 0; }
                        using (HttpRequestMessage req = BuildRequest(targetUrl, -1, -1))
                        using (HttpResponseMessage resp = await SharedHttpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, _cts.Token).ConfigureAwait(false))
                        {
                            resp.EnsureSuccessStatusCode();
                            byte[] netBuf = new byte[131072];
                            using (Stream netStream = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false))
                            using (FileStream fs = new FileStream(partPath, FileMode.Create, FileAccess.Write, FileShare.None, 524288))
                            {
                                while (!_pauseFlag && !_cancelFlag)
                                {
                                    int read = await netStream.ReadAsync(netBuf, 0, netBuf.Length, _cts.Token).ConfigureAwait(false);
                                    if (read <= 0) break;
                                    limiter.Consume(read);
                                    fs.Write(netBuf, 0, read);
                                    lock (SyncLock) { Segments[segIdx].Downloaded += read; }
                                }
                            }
                        }
                        if (!_pauseFlag && !_cancelFlag) { lock (SyncLock) { Segments[segIdx].Done = true; } }
                        return;
                    }
                    catch (Exception ex)
                    {
                        if (_pauseFlag || _cancelFlag) return;
                        if (attempt == maxRetries - 1) { Status = DownloadState.Error; ErrorMessage = ex.Message; return; }
                        await Task.Delay(300 * (1 << Math.Min(attempt, 4))).ConfigureAwait(false);
                    }
                }
            }
        }

        private void MergeTempSegments()
        {
            string target = FullFilePath;
            if (File.Exists(target))
            {
                string dir = Path.GetDirectoryName(target);
                string stem = Path.GetFileNameWithoutExtension(target);
                string ext = Path.GetExtension(target);
                int counter = 1;
                while (File.Exists(Path.Combine(dir, string.Format("{0} ({1}){2}", stem, counter, ext)))) counter++;
                FileName = string.Format("{0} ({1}){2}", stem, counter, ext);
                target = FullFilePath;
            }
            byte[] buf = new byte[1048576];
            using (FileStream outFs = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None, 1048576))
            {
                for (int i = 0; i < Segments.Count; i++)
                {
                    string partPath = Path.Combine(TempDirPath, string.Format("part_{0:D5}.tmp", i));
                    if (!File.Exists(partPath)) continue;
                    using (FileStream inFs = new FileStream(partPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1048576))
                    {
                        int read;
                        while ((read = inFs.Read(buf, 0, buf.Length)) > 0) outFs.Write(buf, 0, read);
                    }
                }
            }
            try { Directory.Delete(TempDirPath, true); } catch { }
        }

        private void FinalizeCompletedFile(string filePath)
        {
            if (string.IsNullOrEmpty(filePath) || !File.Exists(filePath)) return;
            if (ComputeSha256 || !string.IsNullOrWhiteSpace(ExpectedSha256))
            {
                try
                {
                    using (SHA256 sha = SHA256.Create())
                    using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 1048576))
                    {
                        byte[] hash = sha.ComputeHash(fs);
                        Sha256Hash = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                    }
                    if (!string.IsNullOrWhiteSpace(ExpectedSha256))
                    {
                        ChecksumMismatch = !string.Equals(Sha256Hash, ExpectedSha256.Trim().Replace(" ", "").ToLowerInvariant(), StringComparison.OrdinalIgnoreCase);
                    }
                }
                catch { }
            }
            if (AutoExtractZip && filePath.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) && !ChecksumMismatch)
            {
                try
                {
                    string extractFolder = Path.Combine(Path.GetDirectoryName(filePath), Path.GetFileNameWithoutExtension(filePath));
                    if (!Directory.Exists(extractFolder)) ZipFile.ExtractToDirectory(filePath, extractFolder);
                }
                catch { }
            }
        }

        private static double ParseHumanSizeBytes(string numStr, string unitStr)
        {
            double val;
            if (!double.TryParse(numStr, NumberStyles.Any, CultureInfo.InvariantCulture, out val)) return 0.0;
            string u = (unitStr ?? "").ToUpperInvariant();
            if (u.StartsWith("K")) return val * 1024.0;
            if (u.StartsWith("M")) return val * 1048576.0;
            if (u.StartsWith("G")) return val * 1073741824.0;
            return val;
        }

        private static bool EnsureMediaEngineReady(Action<string> onProgressText)
        {
            string toolsDir = AppPaths.ToolsDir;
            Directory.CreateDirectory(toolsDir);
            string ytdlpExe = Path.Combine(toolsDir, "yt-dlp.exe");
            string ffmpegExe = Path.Combine(toolsDir, "ffmpeg.exe");

            if (!File.Exists(ytdlpExe))
            {
                onProgressText("Initializing YouTube Stream Engine...");
                try
                {
                    using (Stream s = SharedHttpClient.GetStreamAsync("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe").GetAwaiter().GetResult())
                    using (FileStream fs = new FileStream(ytdlpExe, FileMode.Create, FileAccess.Write)) s.CopyTo(fs);
                }
                catch { return false; }
            }
            if (!File.Exists(ffmpegExe))
            {
                onProgressText("Downloading HD Muxer (FFmpeg)...");
                string tmpZip = Path.Combine(toolsDir, "ffmpeg_pkg.zip");
                string extractDir = Path.Combine(toolsDir, "ffmpeg_extract");
                try
                {
                    using (Stream s = SharedHttpClient.GetStreamAsync("https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip").GetAwaiter().GetResult())
                    using (FileStream fs = new FileStream(tmpZip, FileMode.Create, FileAccess.Write)) s.CopyTo(fs);
                    if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true);
                    Directory.CreateDirectory(extractDir);
                    using (Process tarProc = Process.Start(new ProcessStartInfo("tar.exe", string.Format("-xf \"{0}\" -C \"{1}\"", tmpZip, extractDir)) { CreateNoWindow = true, UseShellExecute = false }))
                        tarProc.WaitForExit(60000);
                    string[] found = Directory.GetFiles(extractDir, "ffmpeg.exe", SearchOption.AllDirectories);
                    if (found.Length > 0) File.Copy(found[0], ffmpegExe, true);
                }
                catch { }
                finally
                {
                    try { if (File.Exists(tmpZip)) File.Delete(tmpZip); } catch { }
                    try { if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true); } catch { }
                }
            }
            return File.Exists(ytdlpExe);
        }

        private void RunMediaExtractorDownload(BandwidthLimiter limiter, Action onStateChanged)
        {
            IsStreamPage = true;
            SupportsRanges = false;
            DirectWrite = false;
            bool isAudioOnly = string.Equals(StreamFormat, "mp3", StringComparison.OrdinalIgnoreCase);
            Category = isAudioOnly ? "Music" : "Video";
            if (string.IsNullOrEmpty(SaveDir)) SaveDir = Path.Combine(AppPaths.BaseDownloadDir, Category);
            Directory.CreateDirectory(SaveDir);

            if (!EnsureMediaEngineReady(lbl => { if (string.IsNullOrEmpty(FileName)) FileName = lbl; onStateChanged(); }))
            {
                Status = DownloadState.Error; ErrorMessage = "Could not initialize stream engine."; onStateChanged(); return;
            }
            if (_pauseFlag || _cancelFlag) return;

            string ytdlpExe = Path.Combine(AppPaths.ToolsDir, "yt-dlp.exe");
            string ffmpegExe = Path.Combine(AppPaths.ToolsDir, "ffmpeg.exe");
            bool hasFfmpeg = File.Exists(ffmpegExe);

            string outTemplate = Path.Combine(SaveDir, "%(title).150B.%(ext)s");
            StringBuilder args = new StringBuilder();
            args.Append("--newline --progress --no-playlist --no-mtime --windows-filenames ");
            args.Append("--extractor-args \"youtube:player_client=tv,android_vr,ios\" ");
            args.AppendFormat("--concurrent-fragments {0} --http-chunk-size 10M --buffer-size 1M ", Math.Max(8, Math.Min(32, NumThreads)));
            if (hasFfmpeg) args.AppendFormat("--ffmpeg-location \"{0}\" ", AppPaths.ToolsDir);

            if (isAudioOnly) args.Append(hasFfmpeg ? "-f \"ba[ext=m4a]/ba/b\" -x --audio-format mp3 --audio-quality 0 " : "-f \"ba[ext=m4a]/ba/b\" ");
            else args.Append(hasFfmpeg ? "-f \"bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b\" --merge-output-format mp4 " : "-f \"b[ext=mp4]/b\" ");

            double limKbps = limiter.GetLimitKbps();
            if (limKbps > 0.0) args.AppendFormat("--limit-rate {0}K ", (int)limKbps);
            args.AppendFormat("-o \"{0}\" \"{1}\"", outTemplate, Url);

            Status = DownloadState.Downloading;
            onStateChanged();

            string lastErrorLine = "";
            string resolvedOutputPath = "";
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(ytdlpExe, args.ToString())
                {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
                };

                using (Process proc = new Process { StartInfo = psi })
                {
                    _activeExtractorProc = proc;
                    proc.ErrorDataReceived += (s, e) => { if (!string.IsNullOrWhiteSpace(e.Data) && e.Data.Trim().StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase)) lastErrorLine = e.Data.Trim().Substring(6).Trim(); };
                    proc.OutputDataReceived += (s, e) =>
                    {
                        if (string.IsNullOrWhiteSpace(e.Data)) return;
                        string line = e.Data.Trim();
                        if (line.StartsWith("[download] Destination:", StringComparison.OrdinalIgnoreCase))
                        {
                            resolvedOutputPath = line.Substring("[download] Destination:".Length).Trim();
                            FileName = Path.GetFileName(resolvedOutputPath);
                        }
                        else if (line.StartsWith("[Merger] Merging formats into", StringComparison.OrdinalIgnoreCase))
                        {
                            Match mMerge = Regex.Match(line, @"into\s+""([^""]+)""");
                            if (mMerge.Success) { resolvedOutputPath = mMerge.Groups[1].Value; FileName = Path.GetFileName(resolvedOutputPath); }
                            Status = DownloadState.Finalizing; SpeedBps = 0.0;
                        }
                        else if (line.StartsWith("[download]") && line.Contains("%"))
                        {
                            Match mProg = Regex.Match(line, @"\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?\s*([\d\.]+)([KMGT]?i?B)(?:\s+at\s+([\d\.]+)([KMGT]?i?B)/s)?", RegexOptions.IgnoreCase);
                            if (mProg.Success)
                            {
                                double pct;
                                if (double.TryParse(mProg.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out pct)) StreamPercent = pct;
                                double totB = ParseHumanSizeBytes(mProg.Groups[2].Value, mProg.Groups[3].Value);
                                if (totB > 0) { TotalSize = (long)totB; StreamDownloadedBytes = (long)(totB * (StreamPercent / 100.0)); }
                                if (mProg.Groups[4].Success)
                                {
                                    double inst = ParseHumanSizeBytes(mProg.Groups[4].Value, mProg.Groups[5].Value);
                                    SpeedBps = (SpeedBps <= 0.0) ? inst : (0.35 * inst + 0.65 * SpeedBps);
                                }
                            }
                        }
                    };

                    proc.Start();
                    proc.BeginOutputReadLine();
                    proc.BeginErrorReadLine();
                    proc.WaitForExit();
                    _activeExtractorProc = null;

                    if (_cancelFlag) { onStateChanged(); return; }
                    if (_pauseFlag) { Status = DownloadState.Paused; SpeedBps = 0.0; onStateChanged(); return; }

                    if (proc.ExitCode == 0)
                    {
                        StreamPercent = 100.0; SpeedBps = 0.0;
                        string finalFile = (!string.IsNullOrEmpty(resolvedOutputPath) && File.Exists(resolvedOutputPath)) ? resolvedOutputPath : FullFilePath;
                        if (File.Exists(finalFile))
                        {
                            FileInfo fi = new FileInfo(finalFile);
                            TotalSize = fi.Length; StreamDownloadedBytes = fi.Length; FileName = fi.Name;
                            Status = DownloadState.Finalizing; onStateChanged();
                            FinalizeCompletedFile(finalFile);
                        }
                        Status = DownloadState.Completed; onStateChanged();
                    }
                    else
                    {
                        Status = DownloadState.Error; SpeedBps = 0.0;
                        ErrorMessage = string.IsNullOrEmpty(lastErrorLine) ? "Video unavailable." : lastErrorLine;
                        onStateChanged();
                    }
                }
            }
            catch (Exception ex)
            {
                _activeExtractorProc = null;
                Status = DownloadState.Error; SpeedBps = 0.0; ErrorMessage = ex.Message; onStateChanged();
            }
        }

        private async Task RunCoordinator(BandwidthLimiter limiter, Action onStateChanged)
        {
            if (IsStreamPage || IsVideoPageUrl(Url))
            {
                RunMediaExtractorDownload(limiter, onStateChanged);
                return;
            }

            if (DirectWrite && Segments.Count > 0 && !File.Exists(FullFilePath))
                lock (SyncLock) { Segments.Clear(); }

            if (TotalSize <= 0 || string.IsNullOrEmpty(FileName) || string.IsNullOrEmpty(SaveDir))
            {
                if (!ProbeServer())
                {
                    Status = DownloadState.Error; SpeedBps = 0.0; onStateChanged(); return;
                }
            }

            Directory.CreateDirectory(SaveDir);
            if (!InitializeSegments()) { Status = DownloadState.Error; SpeedBps = 0.0; onStateChanged(); return; }
            if (!DirectWrite) Directory.CreateDirectory(TempDirPath);
            if (_pauseFlag || _cancelFlag) return;

            Status = DownloadState.Downloading;
            onStateChanged();

            int workerCount = DirectWrite ? NumThreads : Math.Min(NumThreads, Math.Max(1, Segments.Count));
            List<Task> workers = new List<Task>(workerCount);

            for (int w = 0; w < workerCount; w++)
            {
                workers.Add(Task.Run(async () =>
                {
                    while (!_pauseFlag && !_cancelFlag)
                    {
                        int idx = -1;
                        lock (SyncLock)
                        {
                            for (int i = 0; i < Segments.Count; i++)
                            {
                                if (!Segments[i].Done && !Segments[i].Active)
                                {
                                    Segments[i].Active = true;
                                    idx = i;
                                    break;
                                }
                            }
                        }
                        if (idx < 0) idx = StealWorkIndex();
                        if (idx < 0) break;

                        await DownloadSegmentWorkerAsync(idx, limiter).ConfigureAwait(false);
                        lock (SyncLock) { Segments[idx].Active = false; }
                        if (Status == DownloadState.Error) break;
                    }
                }));
            }

            await Task.WhenAll(workers).ConfigureAwait(false);

            if (_cancelFlag)
            {
                try
                {
                    if (DirectWrite && File.Exists(FullFilePath)) File.Delete(FullFilePath);
                    else if (Directory.Exists(TempDirPath)) Directory.Delete(TempDirPath, true);
                }
                catch { }
                onStateChanged();
                return;
            }

            if (_pauseFlag) { Status = DownloadState.Paused; SpeedBps = 0.0; onStateChanged(); return; }
            if (Status == DownloadState.Error) { SpeedBps = 0.0; onStateChanged(); return; }

            bool allDone;
            lock (SyncLock) { allDone = Segments.All(s => s.Done); }

            if (allDone)
            {
                Status = DownloadState.Finalizing; SpeedBps = 0.0; onStateChanged();
                if (!DirectWrite) MergeTempSegments();
                FinalizeCompletedFile(FullFilePath);
                Status = DownloadState.Completed; onStateChanged();
            }
        }
    }

    public static class AppPaths
    {
        public static string BaseDownloadDir
        {
            get
            {
                string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "WinIDM");
                Directory.CreateDirectory(root);
                return root;
            }
        }

        public static string ToolsDir
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "WinIDM", "tools");
                Directory.CreateDirectory(dir);
                return dir;
            }
        }

        public static string SanitizeFileName(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "download.bin";
            string name = raw.Trim();
            foreach (char c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
            name = name.TrimEnd('.', ' ');
            if (name.Length == 0) name = "download.bin";
            return name.Length > 180 ? name.Substring(0, 180) : name;
        }

        public static string DetectCategory(string nameOrUrl)
        {
            if (DownloadTask.IsVideoPageUrl(nameOrUrl)) return "Video";
            string clean = nameOrUrl;
            int q = clean.IndexOfAny(new[] { '?', '#' });
            if (q >= 0) clean = clean.Substring(0, q);
            switch (Path.GetExtension(clean).ToLowerInvariant())
            {
                case ".zip": case ".rar": case ".7z": case ".tar": case ".gz": case ".iso": case ".xz": return "Compressed";
                case ".pdf": case ".doc": case ".docx": case ".xls": case ".xlsx": case ".ppt": case ".pptx": case ".txt": case ".epub": return "Documents";
                case ".mp3": case ".wav": case ".flac": case ".aac": case ".ogg": case ".m4a": case ".opus": return "Music";
                case ".exe": case ".msi": case ".msix": case ".bat": case ".apk": case ".dmg": return "Programs";
                case ".mp4": case ".mkv": case ".avi": case ".mov": case ".webm": case ".flv": case ".m4v": case ".ts": case ".m3u8": return "Video";
                default: return "General";
            }
        }

        public static string FormatBytes(double bytes)
        {
            if (bytes < 0) return "Unknown";
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            int idx = 0;
            while (bytes >= 1024.0 && idx < 4) { bytes /= 1024.0; idx++; }
            return idx == 0 ? string.Format("{0:0} B", bytes) : string.Format("{0:0.00} {1}", bytes, units[idx]);
        }

        public static string FormatDuration(double sec)
        {
            if (sec < 0 || double.IsInfinity(sec) || double.IsNaN(sec)) return "--:--";
            long s = (long)sec;
            long h = s / 3600, m = (s % 3600) / 60, rem = s % 60;
            return h > 0 ? string.Format("{0}h {1:D2}m {2:D2}s", h, m, rem) : string.Format("{0:D2}m {1:D2}s", m, rem);
        }

        public static bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                    return key != null && key.GetValue("WinIDM") != null;
            }
            catch { return false; }
        }

        public static void SetStartupEnabled(bool enable)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (key == null) return;
                    if (enable) key.SetValue("WinIDM", "\"" + Application.ExecutablePath + "\" --minimized");
                    else key.DeleteValue("WinIDM", false);
                }
            }
            catch { }
        }
    }

    public class BrowserBridgeServer
    {
        private TcpListener _listener;
        private volatile bool _running;
        private readonly Action<List<string>, Dictionary<string, string>> _onUrlsReceived;

        public BrowserBridgeServer(Action<List<string>, Dictionary<string, string>> onUrlsReceived)
        {
            _onUrlsReceived = onUrlsReceived;
        }

        public void Start()
        {
            try
            {
                _listener = new TcpListener(IPAddress.Loopback, 17892);
                _listener.Start();
                _running = true;
                Task.Run(AcceptLoopAsync);
            }
            catch { }
        }

        public void Stop()
        {
            _running = false;
            try { if (_listener != null) _listener.Stop(); } catch { }
        }

        private async Task AcceptLoopAsync()
        {
            while (_running)
            {
                try
                {
                    TcpClient client = await _listener.AcceptTcpClientAsync().ConfigureAwait(false);
                    _ = Task.Run(() => HandleClientAsync(client));
                }
                catch { break; }
            }
        }

        private async Task HandleClientAsync(TcpClient client)
        {
            using (client)
            using (NetworkStream ns = client.GetStream())
            {
                byte[] buf = new byte[16384];
                StringBuilder raw = new StringBuilder();
                int contentLen = -1;
                int headerEnd = -1;

                while (true)
                {
                    int n = await ns.ReadAsync(buf, 0, buf.Length).ConfigureAwait(false);
                    if (n <= 0) break;
                    raw.Append(Encoding.UTF8.GetString(buf, 0, n));
                    string cur = raw.ToString();
                    if (headerEnd < 0)
                    {
                        headerEnd = cur.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                        if (headerEnd >= 0)
                        {
                            Match mCl = Regex.Match(cur.Substring(0, headerEnd), @"Content-Length:\s*(\d+)", RegexOptions.IgnoreCase);
                            contentLen = mCl.Success ? int.Parse(mCl.Groups[1].Value) : 0;
                        }
                    }
                    if (headerEnd >= 0 && Encoding.UTF8.GetByteCount(cur.Substring(headerEnd + 4)) >= contentLen) break;
                }

                string fullReq = raw.ToString();
                if (fullReq.StartsWith("OPTIONS ", StringComparison.OrdinalIgnoreCase))
                {
                    byte[] optResp = Encoding.UTF8.GetBytes("HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\n\r\n");
                    await ns.WriteAsync(optResp, 0, optResp.Length).ConfigureAwait(false);
                    return;
                }

                if (headerEnd >= 0)
                {
                    string body = fullReq.Substring(headerEnd + 4);
                    List<string> urls = new List<string>();
                    Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                    Match arrMatch = Regex.Match(body, @"""urls""\s*:\s*\[([^\]]*)\]", RegexOptions.IgnoreCase);
                    string scope = arrMatch.Success ? arrMatch.Groups[1].Value : body;
                    foreach (Match m in Regex.Matches(scope, @"""((?:\\.|[^""\\])*)"""))
                    {
                        string u = Regex.Unescape(m.Groups[1].Value);
                        if (u.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || u.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                            urls.Add(u);
                    }
                    foreach (Match hm in Regex.Matches(body, @"""(Referer|Cookie|User-Agent)""\s*:\s*""((?:\\.|[^""\\])*)""", RegexOptions.IgnoreCase))
                    {
                        headers[hm.Groups[1].Value] = Regex.Unescape(hm.Groups[2].Value);
                    }

                    if (urls.Count > 0 && _onUrlsReceived != null) _onUrlsReceived(urls, headers);
                }

                byte[] okResp = Encoding.UTF8.GetBytes("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}");
                await ns.WriteAsync(okResp, 0, okResp.Length).ConfigureAwait(false);
            }
        }
    }

    public class MainForm : Form
    {
        private readonly List<DownloadTask> _tasks = new List<DownloadTask>();
        private readonly BandwidthLimiter _limiter = new BandwidthLimiter();
        private BrowserBridgeServer _bridge;
        private System.Windows.Forms.Timer _uiTimer;
        private NotifyIcon _trayIcon;

        private MenuStrip _menuStrip;
        private ToolStrip _toolStrip;
        private ToolStripTextBox _searchBox;
        private SplitContainer _splitContainer;
        private TreeView _treeCategories;
        private BufferedListView _listDownloads;
        private BufferedPanel _vizPanel;
        private StatusStrip _statusStrip;
        private ToolStripStatusLabel _lblLeftStatus;
        private ToolStripStatusLabel _lblRightStatus;
        private ImageList _catImageList;

        private string _activeFilter = "All Downloads";
        private string _searchQuery = "";
        private string _selectedTaskId = "";
        private int _defaultThreads = 16;
        private int _maxConcurrent = 3;
        private bool _verifySha256 = true;
        private bool _autoExtractZip = false;
        private bool _darkMode = false;
        private bool _forceExit = false;
        private readonly Queue<double> _speedHistory = new Queue<double>(Enumerable.Repeat(0.0, 60));

        public MainForm(bool startMinimized, bool firstRun)
        {
            this.Text = "Internet Download Manager 6.43";
            this.Size = new Size(1240, 740);
            this.MinimumSize = new Size(920, 540);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.AllowDrop = true;
            this.Icon = CreateAppIcon();

            BuildUi();
            LoadState();
            ApplyTheme();

            if (firstRun)
            {
                try
                {
                    string exe = Application.ExecutablePath;
                    string dir = Path.GetDirectoryName(exe);
                    using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\WinIDM"))
                    {
                        if (key != null)
                        {
                            key.SetValue("DisplayName", "Internet Download Manager");
                            key.SetValue("DisplayVersion", "6.43");
                            key.SetValue("Publisher", "Tonec Inc.");
                            key.SetValue("DisplayIcon", exe);
                            key.SetValue("InstallLocation", dir);
                            key.SetValue("UninstallString", string.Format("cmd.exe /c taskkill /F /IM WinIDM.exe >nul 2>&1 & rmdir /S /Q \"{0}\"", dir));
                        }
                    }
                    string ps = string.Format("$ws = New-Object -ComObject WScript.Shell; foreach ($p in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {{ $s = $ws.CreateShortcut((Join-Path $p 'Internet Download Manager.lnk')); $s.TargetPath = '{0}'; $s.WorkingDirectory = '{1}'; $s.Save() }}", exe.Replace("'", "''"), dir.Replace("'", "''"));
                    Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -WindowStyle Hidden -Command \"" + ps + "\"") { CreateNoWindow = true, UseShellExecute = false });
                }
                catch { }
                AppPaths.SetStartupEnabled(true);
            }

            _bridge = new BrowserBridgeServer((urls, headers) =>
            {
                if (this.IsHandleCreated)
                {
                    this.BeginInvoke((Action)(() =>
                    {
                        foreach (string u in urls) AddDownload(u, "", "", _defaultThreads, "best", headers, true);
                        this.Show(); this.WindowState = FormWindowState.Normal; this.Activate();
                    }));
                }
            });
            _bridge.Start();

            _uiTimer = new System.Windows.Forms.Timer { Interval = 250 };
            _uiTimer.Tick += OnUiTick;
            _uiTimer.Start();

            this.DragEnter += (s, e) => { if (e.Data.GetDataPresent(DataFormats.Text) || e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy; };
            this.DragDrop += OnFormDragDrop;
            this.FormClosing += OnFormClosing;

            if (startMinimized) { this.WindowState = FormWindowState.Minimized; this.ShowInTaskbar = false; }
            DispatchQueue();
        }

        private static Icon CreateAppIcon()
        {
            using (Bitmap bmp = new Bitmap(32, 32))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(0, 0, 32, 32), Color.FromArgb(37, 99, 235), Color.FromArgb(16, 185, 129), 45f))
                    g.FillEllipse(br, 1, 1, 30, 30);
                using (Pen p = new Pen(Color.White, 3.2f) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                {
                    g.DrawLine(p, 16, 8, 16, 23);
                    g.DrawLine(p, 10, 18, 16, 24);
                    g.DrawLine(p, 22, 18, 16, 24);
                }
                return Icon.FromHandle(bmp.GetHicon());
            }
        }

        private void BuildUi()
        {
            _menuStrip = new MenuStrip();
            ToolStripMenuItem mTasks = new ToolStripMenuItem("Tasks");
            mTasks.DropDownItems.Add("Add New Download...", null, (s, e) => ShowAddUrlDialog());
            mTasks.DropDownItems.Add("Add Batch Wildcard Download...", null, (s, e) => ShowBatchDialog());
            mTasks.DropDownItems.Add(new ToolStripSeparator());
            mTasks.DropDownItems.Add("Exit Completely", null, (s, e) => { _forceExit = true; this.Close(); });

            ToolStripMenuItem mDownloads = new ToolStripMenuItem("Downloads");
            mDownloads.DropDownItems.Add("Resume Selected", null, (s, e) => ResumeSelected());
            mDownloads.DropDownItems.Add("Pause Selected", null, (s, e) => PauseSelected());
            mDownloads.DropDownItems.Add("Stop All", null, (s, e) => { foreach (var t in _tasks) t.Pause(); SaveState(); });
            mDownloads.DropDownItems.Add("Delete Completed", null, (s, e) => { _tasks.RemoveAll(t => t.Status == DownloadState.Completed); RefreshList(); SaveState(); });
            mDownloads.DropDownItems.Add(new ToolStripSeparator());
            mDownloads.DropDownItems.Add("Speed Limiter...", null, (s, e) => ShowSpeedLimitDialog());
            mDownloads.DropDownItems.Add("Options...", null, (s, e) => ShowOptionsDialog());

            ToolStripMenuItem mView = new ToolStripMenuItem("View");
            mView.DropDownItems.Add("Toggle Light / Midnight Dark Theme", null, (s, e) => { _darkMode = !_darkMode; ApplyTheme(); SaveState(); });

            _menuStrip.Items.AddRange(new ToolStripItem[] { mTasks, mDownloads, mView });

            _toolStrip = new ToolStrip { ImageScalingSize = new Size(28, 28), GripStyle = ToolStripGripStyle.Hidden, Padding = new Padding(4, 2, 4, 2) };
            Action<string, string, EventHandler> addBtn = (text, iconKey, handler) =>
            {
                ToolStripButton b = new ToolStripButton(text, IdmIconFactory.CreateToolbarIcon(iconKey, 28), handler)
                {
                    TextImageRelation = TextImageRelation.ImageAboveText,
                    Font = new Font("Segoe UI", 8.2f)
                };
                _toolStrip.Items.Add(b);
            };
            addBtn("Add URL", "add", (s, e) => ShowAddUrlDialog());
            addBtn("Resume", "resume", (s, e) => ResumeSelected());
            addBtn("Pause", "pause", (s, e) => PauseSelected());
            addBtn("Stop All", "stopall", (s, e) => { foreach (var t in _tasks) t.Pause(); SaveState(); });
            addBtn("Delete", "delete", (s, e) => DeleteSelected());
            addBtn("Del Done", "deldone", (s, e) => { _tasks.RemoveAll(t => t.Status == DownloadState.Completed); RefreshList(); SaveState(); });
            _toolStrip.Items.Add(new ToolStripSeparator());
            addBtn("Batch", "batch", (s, e) => ShowBatchDialog());
            addBtn("Grabber", "grabber", (s, e) => ShowSiteGrabberDialog());
            addBtn("Speed Limit", "speed", (s, e) => ShowSpeedLimitDialog());
            addBtn("Browser Ext", "browser", (s, e) => OpenBrowserExtFolder());
            addBtn("Options", "options", (s, e) => ShowOptionsDialog());

            _searchBox = new ToolStripTextBox { Width = 170, Alignment = ToolStripItemAlignment.Right };
            _searchBox.TextChanged += (s, e) => { _searchQuery = _searchBox.Text.Trim(); RefreshList(); };
            _toolStrip.Items.Add(_searchBox);
            _toolStrip.Items.Add(new ToolStripLabel("Filter:") { Alignment = ToolStripItemAlignment.Right });

            _splitContainer = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 205, FixedPanel = FixedPanel.Panel1 };

            _catImageList = new ImageList { ImageSize = new Size(16, 16), ColorDepth = ColorDepth.Depth32Bit };
            string[] catKeys = { "folder", "unfinished", "finished", "compressed", "documents", "music", "programs", "video" };
            foreach (string k in catKeys) _catImageList.Images.Add(k, IdmIconFactory.CreateCategoryIcon(k));

            _treeCategories = new TreeView { Dock = DockStyle.Fill, ImageList = _catImageList, HideSelection = false, Font = new Font("Segoe UI", 9.2f) };
            TreeNode root = new TreeNode("All Downloads", 0, 0);
            root.Nodes.Add(new TreeNode("Unfinished", 1, 1));
            root.Nodes.Add(new TreeNode("Finished", 2, 2));
            root.Nodes.Add(new TreeNode("Compressed", 3, 3));
            root.Nodes.Add(new TreeNode("Documents", 4, 4));
            root.Nodes.Add(new TreeNode("Music", 5, 5));
            root.Nodes.Add(new TreeNode("Programs", 6, 6));
            root.Nodes.Add(new TreeNode("Video", 7, 7));
            _treeCategories.Nodes.Add(root);
            root.Expand();
            _treeCategories.AfterSelect += (s, e) => { _activeFilter = e.Node.Text; RefreshList(); };
            _splitContainer.Panel1.Controls.Add(_treeCategories);

            _listDownloads = new BufferedListView
            {
                Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, GridLines = true, OwnerDraw = true, SmallImageList = _catImageList, Font = new Font("Segoe UI", 9.0f)
            };
            _listDownloads.Columns.Add("File Name", 280);
            _listDownloads.Columns.Add("Size", 95, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Status", 135);
            _listDownloads.Columns.Add("Time left", 105, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Transfer rate", 115, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Last Try...", 110);
            _listDownloads.Columns.Add("Description", 130);

            _listDownloads.DrawColumnHeader += (s, e) => { e.DrawDefault = true; };
            _listDownloads.DrawItem += (s, e) => { };
            _listDownloads.DrawSubItem += OnDrawSubItem;
            _listDownloads.SelectedIndexChanged += (s, e) =>
            {
                if (_listDownloads.SelectedItems.Count > 0)
                {
                    DownloadTask t = _listDownloads.SelectedItems[0].Tag as DownloadTask;
                    if (t != null) { _selectedTaskId = t.Id; _vizPanel.Invalidate(); }
                }
            };
            _listDownloads.DoubleClick += (s, e) => OpenSelectedFile();

            ContextMenuStrip ctx = new ContextMenuStrip();
            ctx.Items.Add("Open File", null, (s, e) => OpenSelectedFile());
            ctx.Items.Add("Open Containing Folder", null, (s, e) => OpenSelectedFolder());
            ctx.Items.Add(new ToolStripSeparator());
            ctx.Items.Add("Resume Download", null, (s, e) => ResumeSelected());
            ctx.Items.Add("Pause Download", null, (s, e) => PauseSelected());
            ctx.Items.Add("Refresh Expired URL...", null, (s, e) => RefreshSelectedUrl());
            ctx.Items.Add("Copy URL", null, (s, e) => { var t = GetSelectedTask(); if (t != null) Clipboard.SetText(t.Url); });
            ctx.Items.Add("Properties", null, (s, e) => ShowSelectedProperties());
            ctx.Items.Add(new ToolStripSeparator());
            ctx.Items.Add("Remove", null, (s, e) => DeleteSelected());
            _listDownloads.ContextMenuStrip = ctx;

            _vizPanel = new BufferedPanel { Dock = DockStyle.Bottom, Height = 72 };
            _vizPanel.Paint += OnPaintVisualizer;

            _splitContainer.Panel2.Controls.Add(_listDownloads);
            _splitContainer.Panel2.Controls.Add(_vizPanel);

            _statusStrip = new StatusStrip();
            _lblLeftStatus = new ToolStripStatusLabel("Ready") { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
            _lblRightStatus = new ToolStripStatusLabel("Total Speed: 0 B/s") { TextAlign = ContentAlignment.MiddleRight };
            _statusStrip.Items.AddRange(new ToolStripItem[] { _lblLeftStatus, _lblRightStatus });

            _trayIcon = new NotifyIcon { Icon = this.Icon, Text = "Internet Download Manager (Active)", Visible = true };
            ContextMenuStrip trayMenu = new ContextMenuStrip();
            trayMenu.Items.Add("Open IDM", null, (s, e) => { this.Show(); this.ShowInTaskbar = true; this.WindowState = FormWindowState.Normal; this.Activate(); });
            trayMenu.Items.Add("Add New Download...", null, (s, e) => { this.Show(); ShowAddUrlDialog(); });
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("Exit Completely", null, (s, e) => { _forceExit = true; this.Close(); });
            _trayIcon.ContextMenuStrip = trayMenu;
            _trayIcon.DoubleClick += (s, e) => { this.Show(); this.ShowInTaskbar = true; this.WindowState = FormWindowState.Normal; this.Activate(); };

            this.Controls.Add(_splitContainer);
            this.Controls.Add(_toolStrip);
            this.Controls.Add(_menuStrip);
            this.Controls.Add(_statusStrip);
            this.MainMenuStrip = _menuStrip;
        }

        private void ApplyTheme()
        {
            Color bg = _darkMode ? Color.FromArgb(15, 23, 42) : SystemColors.Window;
            Color fg = _darkMode ? Color.FromArgb(226, 232, 240) : SystemColors.WindowText;
            Color bar = _darkMode ? Color.FromArgb(30, 41, 59) : SystemColors.Control;
            _treeCategories.BackColor = bg; _treeCategories.ForeColor = fg;
            _listDownloads.BackColor = bg; _listDownloads.ForeColor = fg;
            _menuStrip.BackColor = bar; _menuStrip.ForeColor = fg;
            _toolStrip.BackColor = bar; _toolStrip.ForeColor = fg;
            _statusStrip.BackColor = bar; _statusStrip.ForeColor = fg;
            _listDownloads.Invalidate(); _vizPanel.Invalidate();
        }

        private void OnDrawSubItem(object sender, DrawListViewSubItemEventArgs e)
        {
            DownloadTask t = e.Item.Tag as DownloadTask;
            bool selected = e.Item.Selected;
            Color bg = selected ? SystemColors.Highlight : _listDownloads.BackColor;
            Color fg = selected ? SystemColors.HighlightText : _listDownloads.ForeColor;
            using (Brush b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, e.Bounds);

            if (e.ColumnIndex == 0 && t != null)
            {
                string catKey = (t.Category ?? "folder").ToLowerInvariant();
                if (!_catImageList.Images.ContainsKey(catKey)) catKey = "folder";
                e.Graphics.DrawImage(_catImageList.Images[catKey], e.Bounds.X + 4, e.Bounds.Y + 2, 16, 16);
                Rectangle txtRect = new Rectangle(e.Bounds.X + 24, e.Bounds.Y, e.Bounds.Width - 26, e.Bounds.Height);
                TextRenderer.DrawText(e.Graphics, e.SubItem.Text, _listDownloads.Font, txtRect, fg, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                return;
            }

            if (e.ColumnIndex == 2 && t != null)
            {
                double pct = t.GetProgressPercent();
                string stText = t.Status == DownloadState.Completed ? "Complete" : (t.Status == DownloadState.Downloading ? string.Format("{0:0.0}%", pct) : t.Status.ToString());
                TextRenderer.DrawText(e.Graphics, stText, _listDownloads.Font, e.Bounds, fg, TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                return;
            }

            TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
            if (e.Header.TextAlign == HorizontalAlignment.Right) flags |= TextFormatFlags.Right;
            TextRenderer.DrawText(e.Graphics, e.SubItem.Text, _listDownloads.Font, e.Bounds, fg, flags);
        }

        private void OnPaintVisualizer(object sender, PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Color.FromArgb(15, 23, 42));
            int w = _vizPanel.Width, h = _vizPanel.Height;
            int sparkW = 220;
            int segAreaW = Math.Max(100, w - sparkW - 24);

            DownloadTask task = _tasks.FirstOrDefault(x => x.Id == _selectedTaskId) ?? _tasks.LastOrDefault();
            if (task != null)
            {
                string title = string.Format("Active Segments ({0})", task.FileName ?? task.Url);
                TextRenderer.DrawText(g, title, new Font("Segoe UI", 8.5f, FontStyle.Bold), new Rectangle(10, 4, segAreaW, 20), Color.FromArgb(226, 232, 240), TextFormatFlags.Left | TextFormatFlags.EndEllipsis);

                lock (task.SyncLock)
                {
                    int n = task.Segments.Count;
                    if (n > 0)
                    {
                        double segW = (double)(segAreaW - 10) / n;
                        using (Brush brSlot = new SolidBrush(Color.FromArgb(30, 41, 59)))
                        using (Brush brDone = new SolidBrush(Color.FromArgb(16, 185, 129)))
                        using (Brush brAct = new SolidBrush(Color.FromArgb(59, 130, 246)))
                        {
                            for (int i = 0; i < n; i++)
                            {
                                DownloadSegment s = task.Segments[i];
                                int x0 = 10 + (int)(i * segW);
                                int x1 = 10 + (int)((i + 1) * segW) - (n > 32 ? 1 : 2);
                                if (x1 <= x0) x1 = x0 + 1;
                                g.FillRectangle(brSlot, x0, 26, x1 - x0, h - 34);

                                double ratio = s.Done || task.Status == DownloadState.Completed ? 1.0
                                    : (task.IsHls ? (s.Downloaded > 0 ? 0.5 : 0.0)
                                    : Math.Min(1.0, (double)Math.Max(0, s.Current - s.Start) / Math.Max(1, s.End - s.Start + 1)));
                                if (ratio > 0)
                                {
                                    int fw = Math.Max(1, (int)((x1 - x0) * ratio));
                                    g.FillRectangle(s.Done || task.Status == DownloadState.Completed ? brDone : brAct, x0, 26, fw, h - 34);
                                }
                            }
                        }
                    }
                }
            }

            int sx0 = segAreaW + 14, sx1 = w - 10;
            using (Brush spBg = new SolidBrush(Color.FromArgb(30, 41, 59))) g.FillRectangle(spBg, sx0, 8, sx1 - sx0, h - 16);
            double peak = _speedHistory.Max();
            TextRenderer.DrawText(g, "Peak: " + AppPaths.FormatBytes(peak) + "/s", new Font("Segoe UI", 8.2f, FontStyle.Bold), new Rectangle(sx0 + 6, 10, sx1 - sx0 - 10, 18), Color.FromArgb(226, 232, 240), TextFormatFlags.Left);

            if (peak > 0)
            {
                double[] pts = _speedHistory.ToArray();
                using (Pen linePen = new Pen(Color.FromArgb(16, 185, 129), 2f))
                {
                    for (int i = 1; i < pts.Length; i++)
                    {
                        int x1 = sx0 + 4 + ((sx1 - sx0 - 8) * (i - 1)) / (pts.Length - 1);
                        int y1 = (h - 12) - (int)((pts[i - 1] / peak) * (h - 38));
                        int x2 = sx0 + 4 + ((sx1 - sx0 - 8) * i) / (pts.Length - 1);
                        int y2 = (h - 12) - (int)((pts[i] / peak) * (h - 38));
                        g.DrawLine(linePen, x1, y1, x2, y2);
                    }
                }
            }
        }

        private void AddDownload(string url, string customName, string saveDir, int threads, string streamFormat, Dictionary<string, string> headers, bool startNow)
        {
            string cleanUrl = (url ?? "").Trim();
            if (!cleanUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && !cleanUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return;

            DownloadTask t = new DownloadTask
            {
                Id = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + "_" + _tasks.Count,
                Url = cleanUrl,
                FileName = string.IsNullOrWhiteSpace(customName) ? "" : AppPaths.SanitizeFileName(customName),
                SaveDir = saveDir ?? "",
                NumThreads = Math.Max(1, Math.Min(32, threads)),
                ComputeSha256 = _verifySha256,
                AutoExtractZip = _autoExtractZip,
                StreamFormat = streamFormat ?? "best",
                Status = startNow ? DownloadState.Queued : DownloadState.Paused
            };
            if (headers != null) foreach (var kv in headers) t.CustomHeaders[kv.Key] = kv.Value;

            _tasks.Add(t);
            _selectedTaskId = t.Id;
            RefreshList();
            SaveState();
            DispatchQueue();
        }

        private void DispatchQueue()
        {
            int active = _tasks.Count(t => t.Status == DownloadState.Downloading || t.Status == DownloadState.Connecting || t.Status == DownloadState.Finalizing);
            foreach (DownloadTask t in _tasks)
            {
                if (active >= _maxConcurrent) break;
                if (t.Status == DownloadState.Queued)
                {
                    t.Start(_limiter, () => { if (this.IsHandleCreated) this.BeginInvoke((Action)(() => { RefreshList(); SaveState(); })); });
                    active++;
                }
            }
        }

        private List<DownloadTask> GetFilteredTasks()
        {
            return _tasks.Where(t =>
            {
                if (!string.IsNullOrEmpty(_searchQuery))
                {
                    string hay = ((t.FileName ?? "") + " " + t.Url).ToLowerInvariant();
                    if (!hay.Contains(_searchQuery.ToLowerInvariant())) return false;
                }
                if (_activeFilter == "All Downloads") return true;
                if (_activeFilter == "Unfinished") return t.Status != DownloadState.Completed;
                if (_activeFilter == "Finished") return t.Status == DownloadState.Completed;
                return string.Equals(t.Category, _activeFilter, StringComparison.OrdinalIgnoreCase);
            }).ToList();
        }

        private void RefreshList()
        {
            List<DownloadTask> visible = GetFilteredTasks();
            _listDownloads.BeginUpdate();
            if (_listDownloads.Items.Count != visible.Count)
            {
                _listDownloads.Items.Clear();
                for (int i = 0; i < visible.Count; i++)
                {
                    ListViewItem item = new ListViewItem(new string[7]) { Tag = visible[i] };
                    _listDownloads.Items.Add(item);
                }
            }
            for (int i = 0; i < visible.Count; i++)
            {
                DownloadTask t = visible[i];
                ListViewItem item = _listDownloads.Items[i];
                item.Tag = t;
                item.SubItems[0].Text = string.IsNullOrEmpty(t.FileName) ? t.Url : t.FileName;
                long dl = t.GetDownloadedBytes();
                item.SubItems[1].Text = t.TotalSize > 0 ? AppPaths.FormatBytes(t.TotalSize) : (dl > 0 ? AppPaths.FormatBytes(dl) : "Unknown");
                item.SubItems[2].Text = t.Status == DownloadState.Completed ? "Complete" : (t.Status == DownloadState.Downloading ? string.Format("{0:0.0}%", t.GetProgressPercent()) : t.Status.ToString());
                item.SubItems[3].Text = (t.Status == DownloadState.Downloading) ? AppPaths.FormatDuration(t.EtaSeconds) : "-";
                item.SubItems[4].Text = (t.Status == DownloadState.Downloading && t.SpeedBps > 0) ? (AppPaths.FormatBytes(t.SpeedBps) + "/s") : "-";
                item.SubItems[5].Text = DateTime.Now.ToString("Nov 18");
                item.SubItems[6].Text = string.IsNullOrEmpty(t.Category) ? "General" : t.Category;
            }
            _listDownloads.EndUpdate();
            _listDownloads.Invalidate();
        }

        private void OnUiTick(object sender, EventArgs e)
        {
            double totalSpeed = 0.0;
            int activeCount = 0;
            foreach (DownloadTask t in _tasks)
            {
                t.UpdateMetrics();
                if (t.Status == DownloadState.Downloading)
                {
                    totalSpeed += t.SpeedBps;
                    activeCount++;
                }
            }
            DispatchQueue();
            RefreshList();
            _speedHistory.Dequeue();
            _speedHistory.Enqueue(totalSpeed);
            _vizPanel.Invalidate();

            double lim = _limiter.GetLimitKbps();
            _lblLeftStatus.Text = string.Format("Tasks: {0} | Active: {1} | Default Threads: {2}", _tasks.Count, activeCount, _defaultThreads);
            _lblRightStatus.Text = string.Format("Speed Limit: {0} | Total Speed: {1}/s", lim <= 0 ? "Unlimited" : (int)lim + " KB/s", AppPaths.FormatBytes(totalSpeed));
        }

        private DownloadTask GetSelectedTask()
        {
            if (_listDownloads.SelectedItems.Count == 0) return null;
            return _listDownloads.SelectedItems[0].Tag as DownloadTask;
        }

        private void ResumeSelected() { var t = GetSelectedTask(); if (t != null && t.Status != DownloadState.Completed) { t.Status = DownloadState.Queued; DispatchQueue(); } }
        private void PauseSelected() { var t = GetSelectedTask(); if (t != null) { t.Pause(); SaveState(); } }
        private void DeleteSelected() { var t = GetSelectedTask(); if (t != null) { t.Cancel(); _tasks.Remove(t); RefreshList(); SaveState(); } }
        private void OpenSelectedFile() { var t = GetSelectedTask(); if (t != null && File.Exists(t.FullFilePath)) Process.Start(new ProcessStartInfo(t.FullFilePath) { UseShellExecute = true }); }
        private void OpenSelectedFolder() { var t = GetSelectedTask(); if (t != null && Directory.Exists(t.SaveDir)) Process.Start("explorer.exe", File.Exists(t.FullFilePath) ? "/select,\"" + t.FullFilePath + "\"" : t.SaveDir); }

        private void RefreshSelectedUrl()
        {
            var t = GetSelectedTask();
            if (t == null) return;
            string newUrl = PromptInput("Refresh Expired URL", "Paste updated download link:", t.Url);
            if (!string.IsNullOrWhiteSpace(newUrl)) { t.Pause(); t.Url = newUrl.Trim(); t.Status = DownloadState.Queued; DispatchQueue(); }
        }

        private void ShowSelectedProperties()
        {
            var t = GetSelectedTask();
            if (t == null) return;
            MessageBox.Show(string.Format("File: {0}\nURL: {1}\nSave Path: {2}\nSize: {3}\nSHA-256: {4}",
                t.FileName, t.Url, t.FullFilePath, AppPaths.FormatBytes(t.TotalSize), string.IsNullOrEmpty(t.Sha256Hash) ? "(Pending)" : t.Sha256Hash),
                "Download Properties", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void OpenBrowserExtFolder()
        {
            string dir = AppPaths.GenerateBrowserExtension();
            if (MessageBox.Show("Browser extension generated at:\n" + dir + "\n\nLoad unpacked in chrome://extensions or edge://extensions.\nOpen folder now?",
                "Browser Extension", MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                Process.Start("explorer.exe", dir);
        }

        private void ShowAddUrlDialog(string prefill = "")
        {
            using (Form dlg = new Form { Text = "Add New Download", Size = new Size(540, 330), StartPosition = FormStartPosition.CenterParent, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false })
            {
                Label l1 = new Label { Text = "Download URL (Direct File, .m3u8, or YouTube):", Left = 14, Top = 14, Width = 490 };
                TextBox tbUrl = new TextBox { Left = 14, Top = 36, Width = 494, Text = string.IsNullOrEmpty(prefill) ? "https://" : prefill };

                Label lDir = new Label { Text = "Save Folder:", Left = 14, Top = 70, Width = 490 };
                TextBox tbDir = new TextBox { Left = 14, Top = 92, Width = 390, Text = Path.Combine(AppPaths.BaseDownloadDir, "General") };
                Button btnBrowse = new Button { Text = "Browse...", Left = 412, Top = 91, Width = 96, Height = 26 };
                btnBrowse.Click += (s, e) =>
                {
                    using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                    {
                        if (fbd.ShowDialog() == DialogResult.OK) tbDir.Text = fbd.SelectedPath;
                    }
                };

                Label l2 = new Label { Text = "Custom File Name (optional):", Left = 14, Top = 126, Width = 310 };
                TextBox tbName = new TextBox { Left = 14, Top = 148, Width = 310 };
                Label l3 = new Label { Text = "Connections (1-32):", Left = 340, Top = 126, Width = 168 };
                NumericUpDown numThr = new NumericUpDown { Left = 340, Top = 148, Width = 168, Minimum = 1, Maximum = 32, Value = _defaultThreads };

                Label l4 = new Label { Text = "YouTube / Stream Quality:", Left = 14, Top = 184, Width = 240 };
                ComboBox cbQual = new ComboBox { Left = 14, Top = 206, Width = 240, DropDownStyle = ComboBoxStyle.DropDownList };
                cbQual.Items.AddRange(new object[] { "best", "1080p", "720p", "mp3" });
                cbQual.SelectedIndex = 0;

                Button btnNow = new Button { Text = "Download Now", Left = 280, Top = 242, Width = 110, Height = 32, DialogResult = DialogResult.OK };
                Button btnLater = new Button { Text = "Add Paused", Left = 398, Top = 242, Width = 110, Height = 32, DialogResult = DialogResult.Ignore };
                dlg.Controls.AddRange(new Control[] { l1, tbUrl, lDir, tbDir, btnBrowse, l2, tbName, l3, numThr, l4, cbQual, btnNow, btnLater });
                dlg.AcceptButton = btnNow;

                DialogResult res = dlg.ShowDialog(this);
                if (res == DialogResult.OK || res == DialogResult.Ignore)
                {
                    AddDownload(tbUrl.Text, tbName.Text, tbDir.Text, (int)numThr.Value, cbQual.SelectedItem.ToString(), null, res == DialogResult.OK);
                }
            }
        }

        private void ShowBatchDialog()
        {
            string pat = PromptInput("Batch Wildcard Grabber", "Enter URL with [01-20] range:", "https://example.com/part_[01-05].zip");
            if (string.IsNullOrWhiteSpace(pat)) return;
            Match m = Regex.Match(pat.Trim(), @"\[(\d+)-(\d+)\]");
            if (m.Success)
            {
                int a = int.Parse(m.Groups[1].Value), b = int.Parse(m.Groups[2].Value), pad = m.Groups[1].Value.Length;
                int step = a <= b ? 1 : -1;
                for (int v = a; (step > 0 ? v <= b : v >= b); v += step)
                {
                    string expanded = pat.Substring(0, m.Index) + v.ToString("D" + pad) + pat.Substring(m.Index + m.Length);
                    AddDownload(expanded, "", "", _defaultThreads, "best", null, true);
                }
            }
            else AddDownload(pat, "", "", _defaultThreads, "best", null, true);
        }

        private void ShowSiteGrabberDialog()
        {
            string pageUrl = PromptInput("Site Grabber", "Enter webpage URL to scan for downloadable files:", "https://");
            if (string.IsNullOrWhiteSpace(pageUrl) || !pageUrl.StartsWith("http")) return;
            try
            {
                using (WebClient wc = new WebClient { Proxy = null })
                {
                    wc.Headers.Add("User-Agent", "Mozilla/5.0");
                    string html = wc.DownloadString(pageUrl);
                    Uri baseUri = new Uri(pageUrl);
                    HashSet<string> links = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (Match m in Regex.Matches(html, @"(?:href|src)\s*=\s*[""']([^""'#]+)[""']", RegexOptions.IgnoreCase))
                    {
                        Uri abs;
                        if (Uri.TryCreate(baseUri, m.Groups[1].Value, out abs) && (abs.Scheme == "http" || abs.Scheme == "https"))
                        {
                            if (AppPaths.DetectCategory(abs.ToString()) != "General") links.Add(abs.ToString());
                        }
                    }
                    if (links.Count == 0) { MessageBox.Show("No direct media or archive files found on page."); return; }
                    if (MessageBox.Show("Found " + links.Count + " files. Download all?", "Site Grabber", MessageBoxButtons.YesNo) == DialogResult.Yes)
                    {
                        var hdr = new Dictionary<string, string> { { "Referer", pageUrl } };
                        foreach (string u in links) AddDownload(u, "", "", _defaultThreads, "best", hdr, true);
                    }
                }
            }
            catch (Exception ex) { MessageBox.Show("Scan error: " + ex.Message); }
        }

        private void ShowSpeedLimitDialog()
        {
            string val = PromptInput("Global Speed Limiter", "Max download speed in KB/s (0 = Unlimited):", ((int)_limiter.GetLimitKbps()).ToString());
            double kbps;
            if (double.TryParse(val, out kbps)) { _limiter.SetLimitKbps(Math.Max(0, kbps)); SaveState(); }
        }

        private void ShowOptionsDialog()
        {
            using (Form dlg = new Form { Text = "IDM Options", Size = new Size(420, 240), StartPosition = FormStartPosition.CenterParent, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false })
            {
                Label l1 = new Label { Text = "Default Parallel Connections (1-32):", Left = 16, Top = 20, Width = 240 };
                NumericUpDown numThr = new NumericUpDown { Left = 270, Top = 18, Width = 110, Minimum = 1, Maximum = 32, Value = _defaultThreads };
                Label l2 = new Label { Text = "Max Simultaneous Downloads (1-10):", Left = 16, Top = 56, Width = 240 };
                NumericUpDown numCon = new NumericUpDown { Left = 270, Top = 54, Width = 110, Minimum = 1, Maximum = 10, Value = _maxConcurrent };
                CheckBox chkSha = new CheckBox { Text = "Verify SHA-256 checksum on completion", Left = 16, Top = 94, Width = 360, Checked = _verifySha256 };
                CheckBox chkZip = new CheckBox { Text = "Auto-extract .ZIP archives on completion", Left = 16, Top = 122, Width = 360, Checked = _autoExtractZip };
                Button btnSave = new Button { Text = "Save", Left = 290, Top = 158, Width = 90, Height = 30, DialogResult = DialogResult.OK };
                dlg.Controls.AddRange(new Control[] { l1, numThr, l2, numCon, chkSha, chkZip, btnSave });
                if (dlg.ShowDialog(this) == DialogResult.OK)
                {
                    _defaultThreads = (int)numThr.Value;
                    _maxConcurrent = (int)numCon.Value;
                    _verifySha256 = chkSha.Checked;
                    _autoExtractZip = chkZip.Checked;
                    SaveState();
                }
            }
        }

        private string PromptInput(string title, string prompt, string initial)
        {
            using (Form f = new Form { Text = title, Size = new Size(460, 165), StartPosition = FormStartPosition.CenterParent, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false })
            {
                Label lbl = new Label { Text = prompt, Left = 14, Top = 14, Width = 415 };
                TextBox tb = new TextBox { Left = 14, Top = 38, Width = 415, Text = initial };
                Button ok = new Button { Text = "OK", Left = 250, Top = 78, Width = 85, Height = 28, DialogResult = DialogResult.OK };
                Button cancel = new Button { Text = "Cancel", Left = 344, Top = 78, Width = 85, Height = 28, DialogResult = DialogResult.Cancel };
                f.Controls.AddRange(new Control[] { lbl, tb, ok, cancel });
                f.AcceptButton = ok;
                return f.ShowDialog(this) == DialogResult.OK ? tb.Text : null;
            }
        }

        private void OnFormDragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.Text))
            {
                string txt = e.Data.GetData(DataFormats.Text) as string;
                if (!string.IsNullOrWhiteSpace(txt)) AddDownload(txt.Trim(), "", "", _defaultThreads, "best", null, true);
            }
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (!_forceExit && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true; this.Hide(); this.ShowInTaskbar = false; SaveState(); return;
            }
            if (_uiTimer != null) _uiTimer.Stop();
            foreach (var t in _tasks) t.Pause();
            SaveState();
            if (_bridge != null) _bridge.Stop();
            if (_trayIcon != null) _trayIcon.Visible = false;
        }

        private void SaveState()
        {
            try
            {
                string path = Path.Combine(AppPaths.BaseDownloadDir, "idm_state.tsv");
                List<string> lines = new List<string>
                {
                    string.Format("CFG\t{0}\t{1}\t{2}\t{3}\t{4}\t{5}", _defaultThreads, _maxConcurrent, (int)_limiter.GetLimitKbps(), _verifySha256 ? 1 : 0, _autoExtractZip ? 1 : 0, _darkMode ? 1 : 0)
                };
                foreach (DownloadTask t in _tasks)
                {
                    DownloadState st = (t.Status == DownloadState.Downloading || t.Status == DownloadState.Connecting || t.Status == DownloadState.Finalizing) ? DownloadState.Paused : t.Status;
                    lines.Add(string.Format("TASK\t{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}", t.Id, t.Url, t.FileName ?? "", t.Category ?? "General", t.SaveDir ?? "", t.NumThreads, t.TotalSize, (int)st));
                }
                File.WriteAllLines(path, lines, Encoding.UTF8);
            }
            catch { }
        }

        private void LoadState()
        {
            try
            {
                string path = Path.Combine(AppPaths.BaseDownloadDir, "idm_state.tsv");
                if (!File.Exists(path)) return;
                foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
                {
                    string[] c = line.Split('\t');
                    if (c.Length >= 7 && c[0] == "CFG")
                    {
                        _defaultThreads = Math.Max(1, Math.Min(32, int.Parse(c[1])));
                        _maxConcurrent = Math.Max(1, Math.Min(10, int.Parse(c[2])));
                        _limiter.SetLimitKbps(double.Parse(c[3]));
                        _verifySha256 = c[4] == "1";
                        _autoExtractZip = c[5] == "1";
                        _darkMode = c[6] == "1";
                    }
                    else if (c.Length >= 9 && c[0] == "TASK")
                    {
                        _tasks.Add(new DownloadTask
                        {
                            Id = c[1], Url = c[2], FileName = c[3], Category = c[4], SaveDir = c[5],
                            NumThreads = int.Parse(c[6]), TotalSize = long.Parse(c[7]), Status = (DownloadState)int.Parse(c[8])
                        });
                    }
                }
                RefreshList();
            }
            catch { }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, "WinIDM_SingleInstance_Mutex", out createdNew))
            {
                if (!createdNew) return;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                bool minimized = args.Any(a => a.Equals("--minimized", StringComparison.OrdinalIgnoreCase));
                bool firstRun = args.Any(a => a.Equals("--first-run", StringComparison.OrdinalIgnoreCase));
                Application.Run(new MainForm(minimized, firstRun));
            }
        }
    }
}