@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Launching WinIDM...
echo Starting WinIDM...

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

"%CSC%" /nologo /target:winexe /optimize+ /out:"%EXE_FILE%" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll "%CS_FILE%"
del /f /q "%CS_FILE%" >nul 2>&1

if not exist "%EXE_FILE%" (
    echo [ERROR] Could not initialize WinIDM. Please ensure .NET Framework 4.x is enabled in Windows.
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
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WinIDMApp
{
    // ========================================================================
    // DOUBLE-BUFFERED CONTROLS FOR FLICKER-FREE REAL-TIME UPDATES
    // ========================================================================
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

    // ========================================================================
    // PROCEDURAL GDI+ VECTOR ICON GENERATOR (IDM TOOLBAR & FILE-TYPE ICONS)
    // ========================================================================
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
                    {
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    using (Pen ring = new Pen(Color.FromArgb(21, 128, 61), 1.5f * s))
                    {
                        g.DrawEllipse(ring, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    using (Pen plus = new Pen(Color.White, 3.6f * s))
                    {
                        plus.StartCap = LineCap.Round;
                        plus.EndCap = LineCap.Round;
                        g.DrawLine(plus, 16 * s, 9 * s, 16 * s, 23 * s);
                        g.DrawLine(plus, 9 * s, 16 * s, 23 * s, 16 * s);
                    }
                }
                else if (kind == "resume")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(52, 211, 153), Color.FromArgb(5, 150, 105), 45f))
                    {
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    PointF[] tri = {
                        new PointF(12.5f * s, 9.5f * s),
                        new PointF(23.0f * s, 16.0f * s),
                        new PointF(12.5f * s, 22.5f * s)
                    };
                    g.FillPolygon(Brushes.White, tri);
                }
                else if (kind == "pause")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(251, 191, 36), Color.FromArgb(217, 119, 6), 45f))
                    {
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    g.FillRectangle(Brushes.White, 11.2f * s, 10 * s, 3.4f * s, 12 * s);
                    g.FillRectangle(Brushes.White, 17.4f * s, 10 * s, 3.4f * s, 12 * s);
                }
                else if (kind == "stopall")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(2, 2, size - 4, size - 4),
                        Color.FromArgb(248, 113, 113), Color.FromArgb(220, 38, 38), 45f))
                    {
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    g.FillRectangle(Brushes.White, 10.5f * s, 10.5f * s, 11 * s, 11 * s);
                }
                else if (kind == "delete")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(4, 4, size - 8, size - 8),
                        Color.FromArgb(239, 68, 68), Color.FromArgb(185, 28, 28), 90f))
                    {
                        g.FillRectangle(br, 8 * s, 9 * s, 16 * s, 18 * s);
                    }
                    using (Pen lid = new Pen(Color.FromArgb(153, 27, 27), 2.4f * s))
                    {
                        lid.StartCap = LineCap.Round;
                        lid.EndCap = LineCap.Round;
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
                    {
                        g.FillEllipse(br, 3 * s, 3 * s, 26 * s, 26 * s);
                    }
                    using (Pen chk = new Pen(Color.White, 3.0f * s))
                    {
                        chk.StartCap = LineCap.Round;
                        chk.EndCap = LineCap.Round;
                        chk.LineJoin = LineJoin.Round;
                        g.DrawLines(chk, new[] {
                            new PointF(9.5f * s, 16.5f * s),
                            new PointF(14.0f * s, 21.0f * s),
                            new PointF(22.5f * s, 11.5f * s)
                        });
                    }
                }
                else if (kind == "options")
                {
                    using (Pen gear = new Pen(Color.FromArgb(71, 85, 105), 4.2f * s))
                    {
                        g.DrawEllipse(gear, 8 * s, 8 * s, 16 * s, 16 * s);
                    }
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
                    using (Brush center = new SolidBrush(Color.FromArgb(59, 130, 246)))
                    {
                        g.FillEllipse(center, 12.5f * s, 12.5f * s, 7 * s, 7 * s);
                    }
                }
                else if (kind == "scheduler")
                {
                    using (Brush face = new SolidBrush(Color.White))
                    {
                        g.FillEllipse(face, 4 * s, 4 * s, 24 * s, 24 * s);
                    }
                    using (Pen rim = new Pen(Color.FromArgb(37, 99, 235), 2.6f * s))
                    {
                        g.DrawEllipse(rim, 4 * s, 4 * s, 24 * s, 24 * s);
                    }
                    using (Pen hand = new Pen(Color.FromArgb(30, 41, 59), 2.4f * s))
                    {
                        hand.StartCap = LineCap.Round;
                        hand.EndCap = LineCap.Round;
                        g.DrawLine(hand, 16 * s, 16 * s, 16 * s, 9 * s);
                        g.DrawLine(hand, 16 * s, 16 * s, 21 * s, 18 * s);
                    }
                }
                else if (kind == "grabber")
                {
                    using (LinearGradientBrush globe = new LinearGradientBrush(new Rectangle(3, 3, size - 6, size - 6),
                        Color.FromArgb(56, 189, 248), Color.FromArgb(2, 132, 199), 45f))
                    {
                        g.FillEllipse(globe, 4 * s, 4 * s, 24 * s, 24 * s);
                    }
                    using (Pen grid = new Pen(Color.FromArgb(210, 255, 255, 255), 1.4f * s))
                    {
                        g.DrawEllipse(grid, 10 * s, 4 * s, 12 * s, 24 * s);
                        g.DrawLine(grid, 4 * s, 16 * s, 28 * s, 16 * s);
                        g.DrawLine(grid, 6 * s, 10 * s, 26 * s, 10 * s);
                        g.DrawLine(grid, 6 * s, 22 * s, 26 * s, 22 * s);
                    }
                }
                else if (kind == "batch")
                {
                    using (Brush backDoc = new SolidBrush(Color.FromArgb(148, 163, 184)))
                    {
                        g.FillRectangle(backDoc, 6 * s, 4 * s, 15 * s, 19 * s);
                    }
                    using (Brush frontDoc = new SolidBrush(Color.FromArgb(59, 130, 246)))
                    {
                        g.FillRectangle(frontDoc, 11 * s, 8 * s, 15 * s, 20 * s);
                    }
                    using (Pen p = new Pen(Color.White, 2.0f * s))
                    {
                        g.DrawLine(p, 14 * s, 14 * s, 23 * s, 14 * s);
                        g.DrawLine(p, 14 * s, 18 * s, 23 * s, 18 * s);
                        g.DrawLine(p, 14 * s, 22 * s, 20 * s, 22 * s);
                    }
                }
                else if (kind == "speed")
                {
                    using (Pen arc = new Pen(Color.FromArgb(234, 88, 12), 3.4f * s))
                    {
                        arc.StartCap = LineCap.Round;
                        arc.EndCap = LineCap.Round;
                        g.DrawArc(arc, 4 * s, 6 * s, 24 * s, 24 * s, 180, 180);
                    }
                    using (Pen needle = new Pen(Color.FromArgb(30, 41, 59), 2.5f * s))
                    {
                        needle.EndCap = LineCap.Round;
                        g.DrawLine(needle, 16 * s, 22 * s, 23 * s, 12 * s);
                    }
                    g.FillEllipse(Brushes.Crimson, 13.5f * s, 19.5f * s, 5 * s, 5 * s);
                }
                else if (kind == "browser")
                {
                    using (LinearGradientBrush br = new LinearGradientBrush(new Rectangle(3, 3, size - 6, size - 6),
                        Color.FromArgb(129, 140, 248), Color.FromArgb(79, 70, 229), 45f))
                    {
                        g.FillRectangle(br, 4 * s, 5 * s, 24 * s, 22 * s);
                    }
                    using (Brush topBar = new SolidBrush(Color.FromArgb(49, 46, 129)))
                    {
                        g.FillRectangle(topBar, 4 * s, 5 * s, 24 * s, 6 * s);
                    }
                    using (Pen arrow = new Pen(Color.White, 2.5f * s))
                    {
                        arrow.StartCap = LineCap.Round;
                        arrow.EndCap = LineCap.Round;
                        g.DrawLine(arrow, 16 * s, 14 * s, 16 * s, 23 * s);
                        g.DrawLine(arrow, 12 * s, 19 * s, 16 * s, 23 * s);
                        g.DrawLine(arrow, 20 * s, 19 * s, 16 * s, 23 * s);
                    }
                }
                else if (kind == "options_small" || kind == "folder")
                {
                    using (Brush tab = new SolidBrush(Color.FromArgb(217, 119, 6)))
                    {
                        g.FillRectangle(tab, 3 * s, 6 * s, 11 * s, 5 * s);
                    }
                    using (LinearGradientBrush body = new LinearGradientBrush(new Rectangle(2, 8, size - 4, size - 10),
                        Color.FromArgb(253, 224, 71), Color.FromArgb(234, 179, 8), 90f))
                    {
                        g.FillRectangle(body, 3 * s, 9 * s, 26 * s, 18 * s);
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
                    using (Brush b = new SolidBrush(Color.FromArgb(225, 29, 72)))
                        g.FillRectangle(b, 1, 2, 14, 12);
                    g.FillPolygon(Brushes.White, new[] { new Point(6, 5), new Point(12, 8), new Point(6, 11) });
                }
                else if (cat == "music")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(147, 51, 234)))
                        g.FillEllipse(b, 1, 1, 14, 14);
                    g.FillEllipse(Brushes.White, 4, 9, 4, 3);
                    g.FillRectangle(Brushes.White, 7, 4, 2, 7);
                    g.FillRectangle(Brushes.White, 7, 4, 5, 2);
                }
                else if (cat == "compressed")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(217, 119, 6)))
                        g.FillRectangle(b, 2, 1, 12, 14);
                    g.FillRectangle(Brushes.White, 7, 2, 2, 12);
                    using (Brush dark = new SolidBrush(Color.FromArgb(120, 53, 15)))
                    {
                        g.FillRectangle(dark, 6, 4, 4, 2);
                        g.FillRectangle(dark, 6, 8, 4, 2);
                    }
                }
                else if (cat == "programs")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(37, 99, 235)))
                        g.FillRectangle(b, 1, 2, 14, 12);
                    g.FillRectangle(Brushes.White, 1, 2, 14, 3);
                    g.FillRectangle(Brushes.White, 4, 7, 8, 4);
                }
                else if (cat == "documents")
                {
                    g.FillRectangle(Brushes.White, 2, 1, 12, 14);
                    using (Pen p = new Pen(Color.FromArgb(2, 132, 199), 1.3f))
                    {
                        g.DrawRectangle(p, 2, 1, 11, 13);
                        g.DrawLine(p, 4, 5, 11, 5);
                        g.DrawLine(p, 4, 8, 11, 8);
                        g.DrawLine(p, 4, 11, 9, 11);
                    }
                }
                else if (cat == "finished" || cat == "completed")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(22, 163, 74)))
                        g.FillEllipse(b, 1, 1, 14, 14);
                    using (Pen p = new Pen(Color.White, 2f))
                        g.DrawLines(p, new[] { new Point(4, 8), new Point(7, 11), new Point(12, 5) });
                }
                else if (cat == "unfinished")
                {
                    using (Brush b = new SolidBrush(Color.FromArgb(234, 88, 12)))
                        g.FillEllipse(b, 1, 1, 14, 14);
                    using (Pen p = new Pen(Color.White, 2f))
                    {
                        g.DrawLine(p, 8, 4, 8, 10);
                        g.DrawLine(p, 5, 8, 8, 11);
                        g.DrawLine(p, 11, 8, 8, 11);
                    }
                }
                else
                {
                    using (Brush tab = new SolidBrush(Color.FromArgb(217, 119, 6)))
                        g.FillRectangle(tab, 1, 2, 6, 3);
                    using (Brush b = new SolidBrush(Color.FromArgb(250, 204, 21)))
                        g.FillRectangle(b, 1, 4, 14, 10);
                }
            }
            return bmp;
        }
    }

    // ========================================================================
    // LOCK-FREE FAST-PATH TOKEN-BUCKET BANDWIDTH LIMITER
    // ========================================================================
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
            lock (_lock)
            {
                return _limitBps / 1024.0;
            }
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

    // ========================================================================
    // DOWNLOAD SEGMENT & TASK ENGINE (32-THREAD LOCK-FREE I/O + YOUTUBE ENGINE)
    // ========================================================================
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
        public string Id;
        public string Url;
        public string FileName;
        public string Category;
        public string SaveDir;
        public int NumThreads;
        public bool ComputeSha256;
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
        private volatile Process _activeExtractorProc = null;
        private long _lastSampleBytes = 0;

        public static bool IsVideoPageUrl(string rawUrl)
        {
            if (string.IsNullOrWhiteSpace(rawUrl)) return false;
            return Regex.IsMatch(rawUrl.Trim(),
                @"^https?://(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch|shorts/|live/|embed/)|youtu\.be/|vimeo\.com/\d+|dailymotion\.com/video/|twitch\.tv/videos/|tiktok\.com/@[^/]+/video/|(?:x|twitter)\.com/[^/]+/status/|facebook\.com/.+/videos/|instagram\.com/(?:p|reel|tv)/)",
                RegexOptions.IgnoreCase);
        }

        public string FullFilePath
        {
            get { return Path.Combine(SaveDir, FileName); }
        }

        public string TempDirPath
        {
            get { return Path.Combine(AppPaths.BaseDownloadDir, ".tmp", Id); }
        }

        public long GetDownloadedBytes()
        {
            if (IsStreamPage)
            {
                return StreamDownloadedBytes;
            }
            lock (SyncLock)
            {
                long sum = 0;
                for (int i = 0; i < Segments.Count; i++)
                {
                    DownloadSegment s = Segments[i];
                    if (!IsHls && s.Start >= 0)
                    {
                        sum += Math.Max(0L, s.Current - s.Start);
                    }
                    else
                    {
                        sum += s.Downloaded;
                    }
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
                    int done = 0;
                    for (int i = 0; i < Segments.Count; i++)
                    {
                        if (Segments[i].Done) done++;
                    }
                    return (100.0 * done) / Segments.Count;
                }
            }
            if (TotalSize <= 0) return 0.0;
            return Math.Min(100.0, (100.0 * GetDownloadedBytes()) / TotalSize);
        }

        public void UpdateMetrics(double dtSec)
        {
            if (Status != DownloadState.Downloading || dtSec <= 0.0)
            {
                SpeedBps = 0.0;
                EtaSeconds = -1.0;
                return;
            }
            if (IsStreamPage)
            {
                return;
            }
            long cur = GetDownloadedBytes();
            long delta = Math.Max(0L, cur - _lastSampleBytes);
            _lastSampleBytes = cur;

            double instant = delta / dtSec;
            SpeedBps = (SpeedBps <= 0.0) ? instant : (0.65 * instant + 0.35 * SpeedBps);

            if (TotalSize > 0 && SpeedBps > 1.0)
            {
                EtaSeconds = Math.Max(0.0, (TotalSize - cur) / SpeedBps);
            }
            else
            {
                EtaSeconds = -1.0;
            }
        }

        public void Start(BandwidthLimiter limiter, Action onStateChanged)
        {
            if (Status == DownloadState.Downloading || Status == DownloadState.Connecting) return;
            _pauseFlag = false;
            _cancelFlag = false;
            ErrorMessage = "";
            Status = DownloadState.Connecting;
            _lastSampleBytes = GetDownloadedBytes();

            Thread t = new Thread(delegate()
            {
                RunCoordinator(limiter, onStateChanged);
            });
            t.IsBackground = true;
            t.Start();
        }

        public void Pause()
        {
            _pauseFlag = true;
            Process p = _activeExtractorProc;
            if (p != null)
            {
                try { if (!p.HasExited) p.Kill(); } catch { }
            }
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
            Process p = _activeExtractorProc;
            if (p != null)
            {
                try { if (!p.HasExited) p.Kill(); } catch { }
            }
        }

        private HttpWebRequest CreateConfiguredRequest(string targetUrl, long rangeStart, long rangeEnd, bool allowCompression)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(targetUrl);
            req.Method = "GET";
            req.AllowAutoRedirect = true;
            req.MaximumAutomaticRedirections = 10;
            req.Timeout = 20000;
            req.ReadWriteTimeout = 25000;
            req.KeepAlive = true;
            req.Pipelinable = true;
            req.ServicePoint.ConnectionLimit = 256;
            req.ServicePoint.UseNagleAlgorithm = false;
            req.ServicePoint.Expect100Continue = false;

            if (allowCompression)
            {
                req.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
            }
            else
            {
                req.AutomaticDecompression = DecompressionMethods.None;
            }

            req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WinIDM/3.4";
            req.Accept = "*/*";

            foreach (KeyValuePair<string, string> kv in CustomHeaders)
            {
                if (string.Equals(kv.Key, "Referer", StringComparison.OrdinalIgnoreCase))
                    req.Referer = kv.Value;
                else if (string.Equals(kv.Key, "User-Agent", StringComparison.OrdinalIgnoreCase))
                    req.UserAgent = kv.Value;
                else if (string.Equals(kv.Key, "Accept", StringComparison.OrdinalIgnoreCase))
                    req.Accept = kv.Value;
                else
                {
                    try { req.Headers[kv.Key] = kv.Value; } catch { }
                }
            }

            if (rangeStart >= 0)
            {
                if (rangeEnd >= rangeStart)
                    req.AddRange(rangeStart, rangeEnd);
                else
                    req.AddRange(rangeStart);
            }
            return req;
        }

        private static string ExtractFileName(HttpWebResponse resp, string finalUrl)
        {
            string cd = resp.Headers["Content-Disposition"];
            if (!string.IsNullOrEmpty(cd))
            {
                Match mStar = Regex.Match(cd, @"filename\*\s*=\s*(?:UTF-8''|utf-8'')?([^;]+)", RegexOptions.IgnoreCase);
                if (mStar.Success)
                {
                    string decoded = Uri.UnescapeDataString(mStar.Groups[1].Value.Trim().Trim('"'));
                    string clean = AppPaths.SanitizeFileName(decoded);
                    if (!string.IsNullOrEmpty(clean) && clean != "download.bin") return clean;
                }
                Match mPlain = Regex.Match(cd, @"filename\s*=\s*""?([^"";]+)""?", RegexOptions.IgnoreCase);
                if (mPlain.Success)
                {
                    string decoded = Uri.UnescapeDataString(mPlain.Groups[1].Value.Trim());
                    string clean = AppPaths.SanitizeFileName(decoded);
                    if (!string.IsNullOrEmpty(clean) && clean != "download.bin") return clean;
                }
            }

            try
            {
                Uri uri = new Uri(finalUrl);
                string seg = Path.GetFileName(Uri.UnescapeDataString(uri.AbsolutePath));
                if (!string.IsNullOrEmpty(seg))
                {
                    return AppPaths.SanitizeFileName(seg);
                }
            }
            catch { }

            return "download.bin";
        }

        private bool ProbeServer()
        {
            HttpWebResponse resp = null;
            try
            {
                HttpWebRequest req = CreateConfiguredRequest(Url, 0, 0, false);
                try
                {
                    resp = (HttpWebResponse)req.GetResponse();
                }
                catch (WebException wex)
                {
                    HttpWebResponse errResp = wex.Response as HttpWebResponse;
                    if (errResp != null && (int)errResp.StatusCode == 416)
                    {
                        errResp.Close();
                        HttpWebRequest retryReq = CreateConfiguredRequest(Url, -1, -1, false);
                        resp = (HttpWebResponse)retryReq.GetResponse();
                    }
                    else
                    {
                        throw;
                    }
                }

                string finalUrl = resp.ResponseUri != null ? resp.ResponseUri.ToString() : Url;
                if (string.IsNullOrEmpty(FileName))
                {
                    FileName = ExtractFileName(resp, finalUrl);
                }

                string lowerUrl = finalUrl.ToLowerInvariant();
                string lowerFn = FileName.ToLowerInvariant();
                if (lowerUrl.Contains(".m3u8") || lowerFn.EndsWith(".m3u8"))
                {
                    resp.Close();
                    return ProbeHlsManifest();
                }

                if (resp.StatusCode == HttpStatusCode.PartialContent)
                {
                    SupportsRanges = true;
                    string cr = resp.Headers["Content-Range"];
                    if (!string.IsNullOrEmpty(cr))
                    {
                        int slash = cr.LastIndexOf('/');
                        if (slash >= 0)
                        {
                            long parsedTotal;
                            if (long.TryParse(cr.Substring(slash + 1).Trim(), out parsedTotal))
                            {
                                TotalSize = parsedTotal;
                            }
                        }
                    }
                }
                else
                {
                    SupportsRanges = false;
                    if (resp.ContentLength > 0)
                    {
                        TotalSize = resp.ContentLength;
                    }
                }

                resp.Close();
                if (string.IsNullOrEmpty(Category)) Category = AppPaths.DetectCategory(FileName);
                if (string.IsNullOrEmpty(SaveDir)) SaveDir = Path.Combine(AppPaths.BaseDownloadDir, Category);
                return true;
            }
            catch (Exception ex)
            {
                if (resp != null) resp.Close();
                ErrorMessage = ex.Message;
                return false;
            }
        }

        private string DownloadTextSync(string targetUrl)
        {
            HttpWebRequest req = CreateConfiguredRequest(targetUrl, -1, -1, true);
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (Stream st = resp.GetResponseStream())
            using (StreamReader sr = new StreamReader(st, Encoding.UTF8))
            {
                return sr.ReadToEnd();
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
                if (string.IsNullOrWhiteSpace(m3u8))
                {
                    ErrorMessage = "Empty HLS .m3u8 playlist.";
                    return false;
                }

                if (m3u8.Contains("#EXT-X-STREAM-INF"))
                {
                    string[] lines = m3u8.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    long bestBw = -1;
                    string bestUri = null;
                    long curBw = 0;

                    for (int i = 0; i < lines.Length; i++)
                    {
                        string line = lines[i].Trim();
                        if (line.StartsWith("#EXT-X-STREAM-INF"))
                        {
                            Match m = Regex.Match(line, @"BANDWIDTH=(\d+)");
                            curBw = m.Success ? long.Parse(m.Groups[1].Value) : 0;
                        }
                        else if (!line.StartsWith("#"))
                        {
                            if (curBw >= bestBw)
                            {
                                bestBw = curBw;
                                bestUri = line;
                            }
                        }
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
                string[] mediaLines = m3u8.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

                for (int i = 0; i < mediaLines.Length; i++)
                {
                    string line = mediaLines[i].Trim();
                    if (line.StartsWith("#EXT-X-KEY:"))
                    {
                        if (!line.Contains("METHOD=NONE")) encrypted = true;
                        continue;
                    }
                    if (line.StartsWith("#EXT-X-MAP:"))
                    {
                        Match m = Regex.Match(line, @"URI=""([^""]+)""");
                        if (m.Success)
                        {
                            initMapUrl = new Uri(new Uri(playlistUrl), m.Groups[1].Value).ToString();
                        }
                        continue;
                    }
                    if (line.StartsWith("#")) continue;
                    segUrls.Add(new Uri(new Uri(playlistUrl), line).ToString());
                }

                if (encrypted)
                {
                    ErrorMessage = "Stream is DRM/AES encrypted and cannot be downloaded.";
                    return false;
                }
                if (segUrls.Count == 0)
                {
                    ErrorMessage = "No media segments found in stream.";
                    return false;
                }

                bool isFmp4 = !string.IsNullOrEmpty(initMapUrl) || segUrls[0].ToLowerInvariant().Contains(".m4s");
                if (isFmp4 && !string.IsNullOrEmpty(initMapUrl))
                {
                    segUrls.Insert(0, initMapUrl);
                }

                if (FileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
                {
                    FileName = Path.ChangeExtension(FileName, isFmp4 ? ".mp4" : ".ts");
                }
                Category = "Video";
                if (string.IsNullOrEmpty(SaveDir))
                {
                    SaveDir = Path.Combine(AppPaths.BaseDownloadDir, Category);
                }

                lock (SyncLock)
                {
                    Segments.Clear();
                    for (int i = 0; i < segUrls.Count; i++)
                    {
                        DownloadSegment seg = new DownloadSegment();
                        seg.Index = i;
                        seg.Start = -1;
                        seg.End = -1;
                        seg.SegmentUrl = segUrls[i];
                        Segments.Add(seg);
                    }
                }
                return true;
            }
            catch (Exception ex)
            {
                ErrorMessage = "HLS Error: " + ex.Message;
                return false;
            }
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
                while (File.Exists(Path.Combine(dir, string.Format("{0} ({1}){2}", stem, counter, ext))))
                {
                    counter++;
                }
                FileName = string.Format("{0} ({1}){2}", stem, counter, ext);
                target = FullFilePath;
            }

            try
            {
                using (FileStream fs = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
                {
                }
                return true;
            }
            catch (Exception ex)
            {
                ErrorMessage = "Disk creation error: " + ex.Message;
                return false;
            }
        }

        private bool InitializeSegments()
        {
            lock (SyncLock)
            {
                if (Segments.Count > 0) return true;

                if (SupportsRanges && TotalSize > 262144 && NumThreads > 1)
                {
                    DirectWrite = true;
                    if (!PrepareDirectFile()) return false;
                    int effectiveThreads = (int)Math.Min((long)NumThreads, Math.Max(1L, TotalSize / 262144L));
                    long chunk = TotalSize / effectiveThreads;
                    for (int i = 0; i < effectiveThreads; i++)
                    {
                        DownloadSegment s = new DownloadSegment();
                        s.Index = i;
                        s.Start = i * chunk;
                        s.End = (i == effectiveThreads - 1) ? (TotalSize - 1) : ((i + 1) * chunk - 1);
                        s.Current = s.Start;
                        Segments.Add(s);
                    }
                }
                else
                {
                    SupportsRanges = false;
                    DirectWrite = false;
                    DownloadSegment s = new DownloadSegment();
                    s.Index = 0;
                    s.Start = 0;
                    s.End = (TotalSize > 0) ? (TotalSize - 1) : -1;
                    s.Current = 0;
                    Segments.Add(s);
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
                        if (rem > bestRem)
                        {
                            bestRem = rem;
                            bestIdx = i;
                        }
                    }
                }
                if (bestIdx < 0 || bestRem < 262144) return -1;

                long mid = Segments[bestIdx].Current + (bestRem / 2);
                long oldEnd = Segments[bestIdx].End;
                Segments[bestIdx].End = mid - 1;

                DownloadSegment stolen = new DownloadSegment();
                stolen.Index = Segments.Count;
                stolen.Start = mid;
                stolen.End = oldEnd;
                stolen.Current = mid;
                stolen.Active = true;
                Segments.Add(stolen);
                return stolen.Index;
            }
        }

        private void DownloadSegmentWorker(int segIdx, BandwidthLimiter limiter)
        {
            string targetUrl;
            lock (SyncLock)
            {
                targetUrl = string.IsNullOrEmpty(Segments[segIdx].SegmentUrl) ? Url : Segments[segIdx].SegmentUrl;
            }

            const int maxRetries = 5;
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
                        if (cur > end)
                        {
                            Segments[segIdx].Done = true;
                            return;
                        }
                    }

                    HttpWebResponse resp = null;
                    try
                    {
                        HttpWebRequest req = CreateConfiguredRequest(targetUrl, cur, end, false);
                        resp = (HttpWebResponse)req.GetResponse();
                        if (cur > 0 && resp.StatusCode != HttpStatusCode.PartialContent)
                        {
                            throw new IOException("Server ignored byte-range header on resume.");
                        }

                        byte[] netBuf = new byte[262144];
                        byte[] writeBuf = new byte[1048576];
                        int writeFill = 0;
                        long writeOffset = cur;

                        using (FileStream localFs = new FileStream(FullFilePath, FileMode.OpenOrCreate, FileAccess.Write, FileShare.ReadWrite, 1048576, FileOptions.RandomAccess))
                        using (Stream netStream = resp.GetResponseStream())
                        {
                            while (!_pauseFlag && !_cancelFlag)
                            {
                                long rem;
                                lock (SyncLock)
                                {
                                    rem = Segments[segIdx].End - Segments[segIdx].Current + 1;
                                }
                                if (rem <= 0) break;

                                int toRead = (int)Math.Min(netBuf.Length, rem);
                                int read = netStream.Read(netBuf, 0, toRead);
                                if (read <= 0) break;

                                limiter.Consume(read);
                                Buffer.BlockCopy(netBuf, 0, writeBuf, writeFill, read);
                                writeFill += read;

                                lock (SyncLock)
                                {
                                    Segments[segIdx].Current += read;
                                }

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
                        resp.Close();

                        lock (SyncLock)
                        {
                            if (Segments[segIdx].Current > Segments[segIdx].End)
                            {
                                Segments[segIdx].Done = true;
                                return;
                            }
                        }
                        if (_pauseFlag || _cancelFlag) return;
                    }
                    catch (Exception ex)
                    {
                        if (resp != null) resp.Close();
                        if (_pauseFlag || _cancelFlag) return;
                        if (attempt == maxRetries - 1)
                        {
                            Status = DownloadState.Error;
                            ErrorMessage = string.Format("Segment {0} failed: {1}", segIdx, ex.Message);
                            return;
                        }
                        Thread.Sleep(400 * (1 << attempt));
                    }
                }
                else
                {
                    string partPath = Path.Combine(TempDirPath, string.Format("part_{0:D5}.tmp", segIdx));
                    HttpWebResponse resp = null;
                    try
                    {
                        lock (SyncLock)
                        {
                            Segments[segIdx].Downloaded = 0;
                        }
                        HttpWebRequest req = CreateConfiguredRequest(targetUrl, -1, -1, false);
                        resp = (HttpWebResponse)req.GetResponse();
                        byte[] netBuf = new byte[262144];

                        using (Stream netStream = resp.GetResponseStream())
                        using (FileStream fs = new FileStream(partPath, FileMode.Create, FileAccess.Write, FileShare.None, 1048576))
                        {
                            while (!_pauseFlag && !_cancelFlag)
                            {
                                int read = netStream.Read(netBuf, 0, netBuf.Length);
                                if (read <= 0) break;
                                limiter.Consume(read);
                                fs.Write(netBuf, 0, read);
                                lock (SyncLock)
                                {
                                    Segments[segIdx].Downloaded += read;
                                }
                            }
                        }
                        resp.Close();

                        if (!_pauseFlag && !_cancelFlag)
                        {
                            lock (SyncLock)
                            {
                                Segments[segIdx].Done = true;
                            }
                        }
                        return;
                    }
                    catch (Exception ex)
                    {
                        if (resp != null) resp.Close();
                        if (_pauseFlag || _cancelFlag) return;
                        if (attempt == maxRetries - 1)
                        {
                            Status = DownloadState.Error;
                            ErrorMessage = string.Format("Segment {0} failed: {1}", segIdx, ex.Message);
                            return;
                        }
                        Thread.Sleep(400 * (1 << attempt));
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
                while (File.Exists(Path.Combine(dir, string.Format("{0} ({1}){2}", stem, counter, ext))))
                {
                    counter++;
                }
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
                        while ((read = inFs.Read(buf, 0, buf.Length)) > 0)
                        {
                            outFs.Write(buf, 0, read);
                        }
                    }
                }
            }

            try { Directory.Delete(TempDirPath, true); } catch { }
        }

        private static string ComputeSha256Hex(string filePath)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 1048576))
            {
                byte[] hash = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder(hash.Length * 2);
                for (int i = 0; i < hash.Length; i++)
                {
                    sb.Append(hash[i].ToString("x2"));
                }
                return sb.ToString();
            }
        }

        private static double ParseHumanSizeBytes(string numStr, string unitStr)
        {
            double val;
            if (!double.TryParse(numStr, NumberStyles.Any, CultureInfo.InvariantCulture, out val)) return 0.0;
            string u = (unitStr ?? "").ToUpperInvariant();
            if (u.StartsWith("K")) return val * 1024.0;
            if (u.StartsWith("M")) return val * 1024.0 * 1024.0;
            if (u.StartsWith("G")) return val * 1024.0 * 1024.0 * 1024.0;
            if (u.StartsWith("T")) return val * 1024.0 * 1024.0 * 1024.0 * 1024.0;
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
                onProgressText("Initializing YouTube Stream Engine (first-time setup)...");
                string tmpYtdlp = ytdlpExe + ".tmp";
                try
                {
                    using (WebClient wc = new WebClient())
                    {
                        wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WinIDM/3.4");
                        wc.DownloadFile("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe", tmpYtdlp);
                    }
                    if (File.Exists(ytdlpExe)) File.Delete(ytdlpExe);
                    File.Move(tmpYtdlp, ytdlpExe);
                }
                catch
                {
                    try { if (File.Exists(tmpYtdlp)) File.Delete(tmpYtdlp); } catch { }
                    return false;
                }
            }

            if (!File.Exists(ffmpegExe))
            {
                onProgressText("Downloading HD Audio/Video Muxer (FFmpeg)...");
                string tmpZip = Path.Combine(toolsDir, "ffmpeg_pkg.zip");
                string extractDir = Path.Combine(toolsDir, "ffmpeg_extract");
                try
                {
                    using (WebClient wc = new WebClient())
                    {
                        wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WinIDM/3.4");
                        wc.DownloadFile("https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip", tmpZip);
                    }
                    if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true);
                    Directory.CreateDirectory(extractDir);

                    ProcessStartInfo tarPsi = new ProcessStartInfo("tar.exe",
                        string.Format("-xf \"{0}\" -C \"{1}\"", tmpZip, extractDir));
                    tarPsi.CreateNoWindow = true;
                    tarPsi.UseShellExecute = false;
                    using (Process tarProc = Process.Start(tarPsi))
                    {
                        tarProc.WaitForExit(60000);
                    }

                    string[] found = Directory.GetFiles(extractDir, "ffmpeg.exe", SearchOption.AllDirectories);
                    if (found.Length > 0)
                    {
                        File.Copy(found[0], ffmpegExe, true);
                    }
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
            Category = "Video";
            if (string.IsNullOrEmpty(SaveDir))
            {
                SaveDir = Path.Combine(AppPaths.BaseDownloadDir, "Video");
            }
            Directory.CreateDirectory(SaveDir);

            bool ready = EnsureMediaEngineReady(delegate(string statusLabel)
            {
                if (string.IsNullOrEmpty(FileName)) FileName = statusLabel;
                onStateChanged();
            });

            if (!ready)
            {
                Status = DownloadState.Error;
                ErrorMessage = "Could not download YouTube stream engine. Check internet connection.";
                onStateChanged();
                return;
            }

            if (_pauseFlag || _cancelFlag) return;

            string ytdlpExe = Path.Combine(AppPaths.ToolsDir, "yt-dlp.exe");
            string ffmpegExe = Path.Combine(AppPaths.ToolsDir, "ffmpeg.exe");
            bool hasFfmpeg = File.Exists(ffmpegExe);

            string outTemplate;
            if (!string.IsNullOrEmpty(FileName) &&
                !FileName.StartsWith("Initializing ", StringComparison.OrdinalIgnoreCase) &&
                !FileName.StartsWith("Downloading ", StringComparison.OrdinalIgnoreCase))
            {
                string stem = Path.GetFileNameWithoutExtension(AppPaths.SanitizeFileName(FileName));
                outTemplate = Path.Combine(SaveDir, stem + ".%(ext)s");
            }
            else
            {
                FileName = "Fetching YouTube video info...";
                outTemplate = Path.Combine(SaveDir, "%(title).150B.%(ext)s");
            }

            StringBuilder args = new StringBuilder();
            args.Append("--newline --progress --no-playlist --no-mtime --windows-filenames ");
            args.Append("--extractor-args \"youtube:player_client=tv,android,web\" ");
            args.AppendFormat("--concurrent-fragments {0} --http-chunk-size 10M ", Math.Max(1, Math.Min(32, NumThreads)));

            if (hasFfmpeg)
            {
                args.AppendFormat("--ffmpeg-location \"{0}\" ", AppPaths.ToolsDir);
                args.Append("-f \"bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b\" --merge-output-format mp4 ");
            }
            else
            {
                args.Append("-f \"b[ext=mp4]/b\" ");
            }

            double limKbps = limiter.GetLimitKbps();
            if (limKbps > 0.0)
            {
                args.AppendFormat("--limit-rate {0}K ", (int)limKbps);
            }

            string ua;
            if (CustomHeaders.TryGetValue("User-Agent", out ua) && !string.IsNullOrEmpty(ua))
            {
                args.AppendFormat("--user-agent \"{0}\" ", ua.Replace("\"", ""));
            }
            string refUrl;
            if (CustomHeaders.TryGetValue("Referer", out refUrl) && !string.IsNullOrEmpty(refUrl))
            {
                args.AppendFormat("--referer \"{0}\" ", refUrl.Replace("\"", ""));
            }

            args.AppendFormat("-o \"{0}\" \"{1}\"", outTemplate, Url);

            Status = DownloadState.Downloading;
            onStateChanged();

            string lastErrorLine = "";
            string resolvedOutputPath = "";

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(ytdlpExe, args.ToString());
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;

                using (Process proc = new Process())
                {
                    proc.StartInfo = psi;
                    _activeExtractorProc = proc;

                    proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (!string.IsNullOrWhiteSpace(e.Data))
                        {
                            string line = e.Data.Trim();
                            if (line.StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase))
                            {
                                lastErrorLine = line.Substring(6).Trim();
                            }
                        }
                    };

                    proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (string.IsNullOrWhiteSpace(e.Data)) return;
                        string line = e.Data.Trim();

                        if (line.StartsWith("[download] Destination:", StringComparison.OrdinalIgnoreCase))
                        {
                            string dest = line.Substring("[download] Destination:".Length).Trim();
                            resolvedOutputPath = dest;
                            FileName = Path.GetFileName(dest);
                        }
                        else if (line.StartsWith("[Merger] Merging formats into", StringComparison.OrdinalIgnoreCase))
                        {
                            Match mMerge = Regex.Match(line, @"into\s+""([^""]+)""");
                            if (mMerge.Success)
                            {
                                resolvedOutputPath = mMerge.Groups[1].Value;
                                FileName = Path.GetFileName(resolvedOutputPath);
                            }
                            Status = DownloadState.Finalizing;
                            SpeedBps = 0.0;
                        }
                        else if (line.Contains("has already been downloaded"))
                        {
                            Match mExist = Regex.Match(line, @"^\[download\]\s+(.+?)\s+has already been downloaded");
                            if (mExist.Success)
                            {
                                resolvedOutputPath = mExist.Groups[1].Value.Trim();
                                FileName = Path.GetFileName(resolvedOutputPath);
                            }
                            StreamPercent = 100.0;
                        }
                        else if (line.StartsWith("[download]") && line.Contains("%"))
                        {
                            Match mProg = Regex.Match(line,
                                @"\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?\s*([\d\.]+)([KMGT]?i?B)(?:\s+at\s+([\d\.]+)([KMGT]?i?B)/s)?(?:\s+ETA\s+(\d+):(\d+))?",
                                RegexOptions.IgnoreCase);
                            if (mProg.Success)
                            {
                                double pct;
                                if (double.TryParse(mProg.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out pct))
                                {
                                    StreamPercent = pct;
                                }
                                double totB = ParseHumanSizeBytes(mProg.Groups[2].Value, mProg.Groups[3].Value);
                                if (totB > 0)
                                {
                                    TotalSize = (long)totB;
                                    StreamDownloadedBytes = (long)(totB * (StreamPercent / 100.0));
                                }
                                if (mProg.Groups[4].Success)
                                {
                                    SpeedBps = ParseHumanSizeBytes(mProg.Groups[4].Value, mProg.Groups[5].Value);
                                }
                                if (mProg.Groups[6].Success && mProg.Groups[7].Success)
                                {
                                    int mins = int.Parse(mProg.Groups[6].Value);
                                    int secs = int.Parse(mProg.Groups[7].Value);
                                    EtaSeconds = mins * 60 + secs;
                                }
                            }
                        }
                    };

                    proc.Start();
                    proc.BeginOutputReadLine();
                    proc.BeginErrorReadLine();
                    proc.WaitForExit();
                    _activeExtractorProc = null;

                    if (_cancelFlag)
                    {
                        if (!string.IsNullOrEmpty(resolvedOutputPath))
                        {
                            try { if (File.Exists(resolvedOutputPath)) File.Delete(resolvedOutputPath); } catch { }
                            try { if (File.Exists(resolvedOutputPath + ".part")) File.Delete(resolvedOutputPath + ".part"); } catch { }
                        }
                        onStateChanged();
                        return;
                    }

                    if (_pauseFlag)
                    {
                        Status = DownloadState.Paused;
                        SpeedBps = 0.0;
                        onStateChanged();
                        return;
                    }

                    if (proc.ExitCode == 0)
                    {
                        StreamPercent = 100.0;
                        SpeedBps = 0.0;
                        string finalFile = !string.IsNullOrEmpty(resolvedOutputPath) && File.Exists(resolvedOutputPath)
                            ? resolvedOutputPath
                            : FullFilePath;
                        if (File.Exists(finalFile))
                        {
                            FileInfo fi = new FileInfo(finalFile);
                            TotalSize = fi.Length;
                            StreamDownloadedBytes = fi.Length;
                            FileName = fi.Name;
                            if (ComputeSha256)
                            {
                                Status = DownloadState.Finalizing;
                                onStateChanged();
                                try { Sha256Hash = ComputeSha256Hex(finalFile); } catch { }
                            }
                        }
                        Status = DownloadState.Completed;
                        onStateChanged();
                    }
                    else
                    {
                        Status = DownloadState.Error;
                        SpeedBps = 0.0;
                        ErrorMessage = string.IsNullOrEmpty(lastErrorLine)
                            ? "Video is DRM-protected or unavailable."
                            : lastErrorLine;
                        onStateChanged();
                    }
                }
            }
            catch (Exception ex)
            {
                _activeExtractorProc = null;
                Status = DownloadState.Error;
                SpeedBps = 0.0;
                ErrorMessage = ex.Message;
                onStateChanged();
            }
        }

        private void RunCoordinator(BandwidthLimiter limiter, Action onStateChanged)
        {
            if (IsStreamPage || IsVideoPageUrl(Url))
            {
                RunMediaExtractorDownload(limiter, onStateChanged);
                return;
            }

            if (DirectWrite && Segments.Count > 0 && !File.Exists(FullFilePath))
            {
                lock (SyncLock) { Segments.Clear(); }
            }

            if (TotalSize <= 0 || string.IsNullOrEmpty(FileName) || string.IsNullOrEmpty(SaveDir))
            {
                if (!ProbeServer())
                {
                    Status = DownloadState.Error;
                    SpeedBps = 0.0;
                    onStateChanged();
                    return;
                }
            }

            Directory.CreateDirectory(SaveDir);
            if (!InitializeSegments())
            {
                Status = DownloadState.Error;
                SpeedBps = 0.0;
                onStateChanged();
                return;
            }
            if (!DirectWrite)
            {
                Directory.CreateDirectory(TempDirPath);
            }

            if (_pauseFlag || _cancelFlag) return;

            Status = DownloadState.Downloading;
            onStateChanged();

            int workerCount = DirectWrite ? NumThreads : Math.Min(NumThreads, Math.Max(1, Segments.Count));
            List<Thread> workers = new List<Thread>(workerCount);

            for (int w = 0; w < workerCount; w++)
            {
                Thread wt = new Thread(delegate()
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
                        if (idx < 0)
                        {
                            idx = StealWorkIndex();
                        }
                        if (idx < 0) break;

                        DownloadSegmentWorker(idx, limiter);
                        lock (SyncLock)
                        {
                            Segments[idx].Active = false;
                        }
                        if (Status == DownloadState.Error) break;
                    }
                });
                wt.IsBackground = true;
                workers.Add(wt);
                wt.Start();
            }

            for (int i = 0; i < workers.Count; i++)
            {
                workers[i].Join();
            }

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

            if (_pauseFlag)
            {
                Status = DownloadState.Paused;
                SpeedBps = 0.0;
                onStateChanged();
                return;
            }

            if (Status == DownloadState.Error)
            {
                SpeedBps = 0.0;
                onStateChanged();
                return;
            }

            bool allDone = true;
            lock (SyncLock)
            {
                for (int i = 0; i < Segments.Count; i++)
                {
                    if (!Segments[i].Done) { allDone = false; break; }
                }
            }

            if (allDone)
            {
                Status = DownloadState.Finalizing;
                SpeedBps = 0.0;
                onStateChanged();

                if (!DirectWrite)
                {
                    MergeTempSegments();
                }
                if (ComputeSha256 && File.Exists(FullFilePath))
                {
                    try { Sha256Hash = ComputeSha256Hex(FullFilePath); } catch { }
                }
                Status = DownloadState.Completed;
                onStateChanged();
            }
        }
    }

    // ========================================================================
    // PATHS, CATEGORIES, STARTUP & BROWSER EXTENSION GENERATOR
    // ========================================================================
    public static class AppPaths
    {
        public static string BaseDownloadDir
        {
            get
            {
                string userProf = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                string root = Path.Combine(userProf, "Downloads", "WinIDM");
                Directory.CreateDirectory(root);
                return root;
            }
        }

        public static string ToolsDir
        {
            get
            {
                string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string dir = Path.Combine(localApp, "Programs", "WinIDM", "tools");
                Directory.CreateDirectory(dir);
                return dir;
            }
        }

        public static string SanitizeFileName(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "download.bin";
            string name = raw.Trim();
            char[] invalid = Path.GetInvalidFileNameChars();
            for (int i = 0; i < invalid.Length; i++)
            {
                name = name.Replace(invalid[i], '_');
            }
            name = name.TrimEnd('.', ' ');
            if (name.Length == 0) name = "download.bin";
            if (name.Length > 180) name = name.Substring(0, 180);
            return name;
        }

        public static string DetectCategory(string nameOrUrl)
        {
            if (DownloadTask.IsVideoPageUrl(nameOrUrl)) return "Video";
            string clean = nameOrUrl;
            int q = clean.IndexOfAny(new[] { '?', '#' });
            if (q >= 0) clean = clean.Substring(0, q);
            string ext = Path.GetExtension(clean).ToLowerInvariant();

            switch (ext)
            {
                case ".zip": case ".rar": case ".7z": case ".tar": case ".gz": case ".iso": case ".xz":
                    return "Compressed";
                case ".pdf": case ".doc": case ".docx": case ".xls": case ".xlsx": case ".ppt": case ".pptx": case ".txt": case ".epub":
                    return "Documents";
                case ".mp3": case ".wav": case ".flac": case ".aac": case ".ogg": case ".m4a": case ".opus":
                    return "Music";
                case ".exe": case ".msi": case ".msix": case ".bat": case ".apk": case ".dmg":
                    return "Programs";
                case ".mp4": case ".mkv": case ".avi": case ".mov": case ".webm": case ".flv": case ".m4v": case ".ts": case ".m3u8":
                    return "Video";
                default:
                    return "General";
            }
        }

        public static string FormatBytes(double bytes)
        {
            if (bytes < 0) return "Unknown";
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            int idx = 0;
            while (bytes >= 1024.0 && idx < 4)
            {
                bytes /= 1024.0;
                idx++;
            }
            return (idx == 0)
                ? string.Format("{0:0} B", bytes)
                : string.Format("{0:0.00} {1}", bytes, units[idx]);
        }

        public static string FormatDuration(double sec)
        {
            if (sec < 0 || double.IsInfinity(sec) || double.IsNaN(sec)) return "--:--";
            long s = (long)sec;
            long h = s / 3600;
            long m = (s % 3600) / 60;
            long rem = s % 60;
            return (h > 0)
                ? string.Format("{0}h {1:D2}m {2:D2}s", h, m, rem)
                : string.Format("{0:D2}m {1:D2}s", m, rem);
        }

        public static bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                {
                    if (key == null) return false;
                    object val = key.GetValue("WinIDM");
                    return val != null && !string.IsNullOrEmpty(val.ToString());
                }
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
                    if (enable)
                    {
                        key.SetValue("WinIDM", "\"" + Application.ExecutablePath + "\" --minimized");
                    }
                    else
                    {
                        key.DeleteValue("WinIDM", false);
                    }
                }
            }
            catch { }
        }

        public static void CreateShortcuts()
        {
            try
            {
                string exe = Application.ExecutablePath;
                string dir = Path.GetDirectoryName(exe);
                string ps = string.Format(
                    "$ws = New-Object -ComObject WScript.Shell; " +
                    "foreach ($p in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {{ " +
                    "$s = $ws.CreateShortcut((Join-Path $p 'WinIDM.lnk')); " +
                    "$s.TargetPath = '{0}'; $s.WorkingDirectory = '{1}'; $s.Save() }}",
                    exe.Replace("'", "''"), dir.Replace("'", "''"));

                ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", "-NoProfile -WindowStyle Hidden -Command \"" + ps + "\"");
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch { }
        }

        public static string GenerateBrowserExtension()
        {
            string extDir = Path.Combine(BaseDownloadDir, "BrowserExtension");
            Directory.CreateDirectory(extDir);

            File.WriteAllText(Path.Combine(extDir, "manifest.json"),
@"{
  ""manifest_version"": 3,
  ""name"": ""WinIDM Integration Module"",
  ""version"": ""3.4"",
  ""description"": ""Captures browser downloads, YouTube videos, cookies, context-menu links, and web streams for WinIDM."",
  ""permissions"": [""downloads"", ""webRequest"", ""activeTab"", ""cookies"", ""contextMenus""],
  ""host_permissions"": [""<all_urls>"", ""http://127.0.0.1:17892/*""],
  ""background"": { ""service_worker"": ""background.js"" },
  ""content_scripts"": [{
    ""matches"": [""<all_urls>""],
    ""js"": [""content.js""],
    ""all_frames"": true,
    ""run_at"": ""document_idle""
  }]
}", Encoding.UTF8);

            File.WriteAllText(Path.Combine(extDir, "background.js"),
@"const BRIDGE = 'http://127.0.0.1:17892/add';
async function sendToWinIDM(url, referer) {
  let cookieStr = '';
  try {
    const cookies = await chrome.cookies.getAll({ url });
    cookieStr = cookies.map(c => `${c.name}=${c.value}`).join('; ');
  } catch (e) {}
  const headers = { 'User-Agent': navigator.userAgent };
  if (referer) headers['Referer'] = referer;
  if (cookieStr) headers['Cookie'] = cookieStr;
  return fetch(BRIDGE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ urls: [url], headers })
  });
}
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: 'winidm-download-link',
      title: 'Download with WinIDM',
      contexts: ['link', 'video', 'audio', 'image', 'page']
    });
  });
});
chrome.contextMenus.onClicked.addListener((info, tab) => {
  const target = info.linkUrl || info.srcUrl || (tab ? tab.url : '');
  if (target && target.startsWith('http')) {
    sendToWinIDM(target, tab ? tab.url : '');
  }
});
chrome.downloads.onCreated.addListener((item) => {
  if (!item.url || !item.url.startsWith('http')) return;
  sendToWinIDM(item.url, item.referrer || '').then((r) => {
    if (r && r.ok) {
      chrome.downloads.cancel(item.id);
      chrome.downloads.erase({ id: item.id });
    }
  }).catch(() => {});
});
chrome.webRequest.onBeforeRequest.addListener((details) => {
  if (details.tabId < 0) return;
  if (details.url.includes('googlevideo.com/videoplayback')) return;
  if (/\.(mp4|webm|m3u8|mp3|m4a|flac)(\?|$)/i.test(details.url)) {
    chrome.tabs.sendMessage(details.tabId, { type: 'WINIDM_MEDIA', url: details.url }).catch(() => {});
  }
}, { urls: ['<all_urls>'] });
chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg.type === 'WINIDM_SEND_MEDIA' && msg.url) {
    sendToWinIDM(msg.url, sender.tab ? sender.tab.url : '');
  }
});", Encoding.UTF8);

            File.WriteAllText(Path.Combine(extDir, "content.js"),
@"let latestMediaUrl = '';
let activeVideo = null;
let lastPageUrl = '';

function isYouTubeVideoPage() {
  const h = location.hostname.toLowerCase();
  const p = location.pathname;
  return (h.includes('youtube.com') && (p.startsWith('/watch') || p.startsWith('/shorts/') || p.startsWith('/live/'))) ||
         h === 'youtu.be';
}

function isDrmProtected(v) {
  if (isYouTubeVideoPage()) return false;
  try { return !!(v && v.mediaKeys); } catch (e) { return false; }
}

function getLargestVideo() {
  let best = null, bestArea = 0;
  for (const v of document.querySelectorAll('video')) {
    if (isDrmProtected(v)) continue;
    const r = v.getBoundingClientRect();
    const area = r.width * r.height;
    if (r.width >= 200 && r.height >= 120 && area > bestArea) {
      bestArea = area;
      best = v;
    }
  }
  return best;
}

function positionPill() {
  const btn = document.getElementById('winidm-float-btn');
  if (!btn) return;
  if (activeVideo && document.contains(activeVideo)) {
    const r = activeVideo.getBoundingClientRect();
    if (r.width >= 200 && r.height >= 120 && r.bottom > 0 && r.top < window.innerHeight) {
      btn.style.top = Math.max(8, r.top + 10) + 'px';
      btn.style.left = Math.max(8, r.right - btn.offsetWidth - 10) + 'px';
      btn.style.right = 'auto';
      return;
    }
  }
  btn.style.top = '16px';
  btn.style.right = '16px';
  btn.style.left = 'auto';
}

function showPill(url, videoEl, customLabel) {
  if (videoEl) {
    if (isDrmProtected(videoEl)) return;
    activeVideo = videoEl;
  }
  if (url && url.startsWith('http')) latestMediaUrl = url;
  if (!latestMediaUrl && activeVideo && activeVideo.currentSrc && activeVideo.currentSrc.startsWith('http')) {
    latestMediaUrl = activeVideo.currentSrc;
  }
  if (!latestMediaUrl) return;

  let btn = document.getElementById('winidm-float-btn');
  if (!btn) {
    btn = document.createElement('button');
    btn.id = 'winidm-float-btn';
    Object.assign(btn.style, {
      position: 'fixed', top: '16px', right: '16px', zIndex: 2147483647,
      background: 'linear-gradient(135deg, #2563eb, #1d4ed8)', color: '#fff',
      border: '1px solid rgba(255,255,255,0.25)', borderRadius: '6px',
      padding: '7px 12px', fontFamily: 'Segoe UI, sans-serif', fontWeight: '600',
      fontSize: '12px', cursor: 'pointer', boxShadow: '0 4px 14px rgba(0,0,0,0.4)'
    });
    btn.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      chrome.runtime.sendMessage({ type: 'WINIDM_SEND_MEDIA', url: latestMediaUrl });
      btn.textContent = 'Sent to WinIDM!';
      setTimeout(() => { if (btn) btn.remove(); }, 2200);
    };
    document.body.appendChild(btn);
  }
  if (btn.textContent !== 'Sent to WinIDM!') {
    if (customLabel) {
      btn.textContent = customLabel;
    } else {
      btn.textContent = /\.m3u8(\?|$)/i.test(latestMediaUrl) ? '⬇ Download video stream' : '⬇ Download this video';
    }
  }
  positionPill();
}

function scanVideos() {
  if (location.href !== lastPageUrl) {
    lastPageUrl = location.href;
    latestMediaUrl = '';
    const old = document.getElementById('winidm-float-btn');
    if (old) old.remove();
  }

  const best = getLargestVideo();
  if (isYouTubeVideoPage()) {
    showPill(location.href, best, '⬇ Download YouTube Video');
    return;
  }
  if (!best) return;
  const src = best.currentSrc || best.src || '';
  if (src.startsWith('http')) showPill(src, best, '');
  else if (latestMediaUrl) showPill(latestMediaUrl, best, '');
}

window.addEventListener('scroll', positionPill, { passive: true });
window.addEventListener('resize', positionPill, { passive: true });
setInterval(scanVideos, 1200);
chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'WINIDM_MEDIA' && !isYouTubeVideoPage()) {
    showPill(msg.url, getLargestVideo(), '');
  }
});", Encoding.UTF8);

            return extDir;
        }
    }

    // ========================================================================
    // EMBEDDED LOCAL HTTP BROWSER BRIDGE (127.0.0.1:17892)
    // ========================================================================
    public class BrowserBridgeServer
    {
        private HttpListener _listener;
        private readonly Action<List<string>, Dictionary<string, string>> _onReceive;

        public BrowserBridgeServer(Action<List<string>, Dictionary<string, string>> onReceive)
        {
            _onReceive = onReceive;
        }

        public void Start()
        {
            try
            {
                _listener = new HttpListener();
                _listener.Prefixes.Add("http://127.0.0.1:17892/");
                _listener.Start();

                Thread t = new Thread(ListenLoop);
                t.IsBackground = true;
                t.Start();
            }
            catch { }
        }

        public void Stop()
        {
            try { if (_listener != null) _listener.Stop(); } catch { }
        }

        private void ListenLoop()
        {
            while (_listener != null && _listener.IsListening)
            {
                try
                {
                    HttpListenerContext ctx = _listener.GetContext();
                    ThreadPool.QueueUserWorkItem(delegate { HandleContext(ctx); });
                }
                catch { break; }
            }
        }

        private void HandleContext(HttpListenerContext ctx)
        {
            try
            {
                ctx.Response.AddHeader("Access-Control-Allow-Origin", "*");
                ctx.Response.AddHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
                ctx.Response.AddHeader("Access-Control-Allow-Headers", "Content-Type");

                if (ctx.Request.HttpMethod == "OPTIONS")
                {
                    ctx.Response.StatusCode = 204;
                    ctx.Response.Close();
                    return;
                }

                string body;
                using (StreamReader sr = new StreamReader(ctx.Request.InputStream, Encoding.UTF8))
                {
                    body = sr.ReadToEnd();
                }

                List<string> urls = new List<string>();
                Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                Match arrMatch = Regex.Match(body, @"""urls""\s*:\s*\[([^\]]*)\]", RegexOptions.IgnoreCase);
                string urlScope = arrMatch.Success ? arrMatch.Groups[1].Value : body;
                foreach (Match m in Regex.Matches(urlScope, @"""((?:\\.|[^""\\])*)"""))
                {
                    string u = Regex.Unescape(m.Groups[1].Value);
                    if (u.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                        u.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                    {
                        urls.Add(u);
                    }
                }

                foreach (Match m in Regex.Matches(body, @"""(Referer|Cookie|User-Agent)""\s*:\s*""((?:\\.|[^""\\])*)""", RegexOptions.IgnoreCase))
                {
                    headers[m.Groups[1].Value] = Regex.Unescape(m.Groups[2].Value);
                }

                if (urls.Count > 0 && _onReceive != null)
                {
                    _onReceive(urls, headers);
                }

                byte[] okBytes = Encoding.UTF8.GetBytes("{\"ok\":true}");
                ctx.Response.ContentType = "application/json";
                ctx.Response.StatusCode = 200;
                ctx.Response.OutputStream.Write(okBytes, 0, okBytes.Length);
                ctx.Response.Close();
            }
            catch
            {
                try { ctx.Response.Close(); } catch { }
            }
        }
    }

    // ========================================================================
    // MAIN WINIDM DESKTOP APPLICATION WINDOW (IDM-STYLE REMODELED GUI)
    // ========================================================================
    public class MainForm : Form
    {
        private bool _darkTheme = false;

        // Dynamic IDM Theme Palette (Classic IDM Light/Steel-Blue & Midnight Dark)
        private Color ColWindowBg;
        private Color ColMenuBg;
        private Color ColToolbarBg;
        private Color ColToolbarHover;
        private Color ColSidebarBg;
        private Color ColListBg;
        private Color ColListAltBg;
        private Color ColHeaderBg;
        private Color ColSelectionBg;
        private Color ColBorder;
        private Color ColTextPrimary;
        private Color ColTextMuted;
        private Color ColAccentBlue;
        private Color ColProgressGreen;

        private MenuStrip _menuStrip;
        private ToolStrip _toolStrip;
        private SplitContainer _splitMain;
        private TreeView _treeCategories;
        private ImageList _catImageList;
        private BufferedListView _listDownloads;
        private BufferedPanel _vizPanel;
        private Panel _statusBar;
        private Label _lblStatusLeft;
        private Label _lblStatusRight;
        private System.Windows.Forms.Timer _uiTimer;
        private NotifyIcon _trayIcon;
        private ContextMenuStrip _listMenu;

        private TreeNode _nodeAll;
        private TreeNode _nodeUnfinished;
        private TreeNode _nodeFinished;
        private readonly Dictionary<string, TreeNode> _subCatNodes = new Dictionary<string, TreeNode>(StringComparer.OrdinalIgnoreCase);

        private readonly BandwidthLimiter _limiter = new BandwidthLimiter();
        private BrowserBridgeServer _bridge;
        private readonly List<DownloadTask> _tasks = new List<DownloadTask>();
        private readonly Queue<double> _speedHistory = new Queue<double>();
        private readonly HashSet<string> _notifiedIds = new HashSet<string>();

        private int _defaultThreads = 16;
        private int _maxConcurrent = 3;
        private bool _verifySha256 = true;
        private bool _clipboardMonitor = false;
        private string _lastClipboard = "";
        private bool _schedulerEnabled = false;
        private int _schedHour = 2;
        private int _schedMin = 0;

        private string _activeFilter = "All Downloads";
        private string _selectedTaskId = null;
        private bool _forceExit = false;
        private int _tickCount = 0;

        public MainForm(bool firstRun)
        {
            for (int i = 0; i < 60; i++) _speedHistory.Enqueue(0.0);

            this.Text = "Internet Download Manager (WinIDM 3.4)";
            this.Size = new Size(1240, 740);
            this.MinimumSize = new Size(940, 560);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Font = new Font("Segoe UI", 9f);
            this.Icon = CreateCustomIcon();
            this.AllowDrop = true;

            LoadState();
            ConfigureThemeColors();
            BuildIDMInterface();
            ApplyThemeToControls();
            SetupTray();

            UpdateTreeCounts();
            RefreshListView();
            DispatchQueue();

            _bridge = new BrowserBridgeServer(delegate(List<string> urls, Dictionary<string, string> headers)
            {
                this.BeginInvoke((Action)delegate
                {
                    for (int i = 0; i < urls.Count; i++)
                    {
                        AddDownload(urls[i], "", "", _defaultThreads, headers, true);
                    }
                    RestoreFromTray();
                });
            });
            _bridge.Start();

            this.DragEnter += delegate(object s, DragEventArgs e)
            {
                if (e.Data.GetDataPresent(DataFormats.Text) || e.Data.GetDataPresent(DataFormats.FileDrop))
                    e.Effect = DragDropEffects.Copy;
            };
            this.DragDrop += MainForm_DragDrop;

            _uiTimer = new System.Windows.Forms.Timer();
            _uiTimer.Interval = 250;
            _uiTimer.Tick += UiTimer_Tick;
            _uiTimer.Start();

            if (firstRun)
            {
                AppPaths.CreateShortcuts();
                AppPaths.GenerateBrowserExtension();
                if (!AppPaths.IsStartupEnabled())
                {
                    AppPaths.SetStartupEnabled(true);
                }
            }
        }

        private void ConfigureThemeColors()
        {
            if (_darkTheme)
            {
                ColWindowBg      = Color.FromArgb(15, 23, 42);
                ColMenuBg        = Color.FromArgb(24, 33, 49);
                ColToolbarBg     = Color.FromArgb(30, 41, 59);
                ColToolbarHover  = Color.FromArgb(51, 65, 85);
                ColSidebarBg     = Color.FromArgb(22, 30, 46);
                ColListBg        = Color.FromArgb(17, 24, 39);
                ColListAltBg     = Color.FromArgb(24, 34, 52);
                ColHeaderBg      = Color.FromArgb(30, 41, 59);
                ColSelectionBg   = Color.FromArgb(37, 99, 235);
                ColBorder        = Color.FromArgb(51, 65, 85);
                ColTextPrimary   = Color.FromArgb(241, 245, 249);
                ColTextMuted     = Color.FromArgb(148, 163, 184);
                ColAccentBlue    = Color.FromArgb(59, 130, 246);
                ColProgressGreen = Color.FromArgb(34, 197, 94);
            }
            else
            {
                // Classic IDM Crisp Light / Steel-Blue Aero Aesthetic
                ColWindowBg      = Color.FromArgb(228, 236, 246);
                ColMenuBg        = Color.FromArgb(243, 246, 251);
                ColToolbarBg     = Color.FromArgb(232, 240, 250);
                ColToolbarHover  = Color.FromArgb(204, 223, 246);
                ColSidebarBg     = Color.FromArgb(248, 250, 252);
                ColListBg        = Color.FromArgb(255, 255, 255);
                ColListAltBg     = Color.FromArgb(246, 249, 253);
                ColHeaderBg      = Color.FromArgb(236, 242, 249);
                ColSelectionBg   = Color.FromArgb(204, 228, 255);
                ColBorder        = Color.FromArgb(196, 210, 226);
                ColTextPrimary   = Color.FromArgb(20, 30, 48);
                ColTextMuted     = Color.FromArgb(90, 106, 128);
                ColAccentBlue    = Color.FromArgb(29, 78, 216);
                ColProgressGreen = Color.FromArgb(34, 197, 94);
            }
        }

        private static Icon CreateCustomIcon()
        {
            Bitmap bmp = IdmIconFactory.CreateToolbarIcon("add", 32);
            return Icon.FromHandle(bmp.GetHicon());
        }

        private void BuildIDMInterface()
        {
            // 1. Classic IDM Top Menu Bar (Tasks | File | Downloads | View | Help)
            _menuStrip = new MenuStrip();
            _menuStrip.Dock = DockStyle.Top;
            _menuStrip.Padding = new Padding(6, 2, 0, 2);

            ToolStripMenuItem mTasks = new ToolStripMenuItem("Tasks");
            mTasks.DropDownItems.Add("Add new download...", null, delegate { OpenAddUrlDialog(""); });
            mTasks.DropDownItems.Add("Add batch download...", null, delegate { OpenBatchDialog(); });
            mTasks.DropDownItems.Add("Run site grabber...", null, delegate { OpenSiteGrabberDialog(); });
            mTasks.DropDownItems.Add(new ToolStripSeparator());
            mTasks.DropDownItems.Add("Exit", null, delegate { _forceExit = true; this.Close(); });

            ToolStripMenuItem mFile = new ToolStripMenuItem("File");
            mFile.DropDownItems.Add("Open", null, delegate { OpenSelectedFile(); });
            mFile.DropDownItems.Add("Open folder", null, delegate { OpenSelectedFolder(); });
            mFile.DropDownItems.Add(new ToolStripSeparator());
            mFile.DropDownItems.Add("Resume", null, delegate { ResumeSelected(); });
            mFile.DropDownItems.Add("Stop / Pause", null, delegate { PauseSelected(); });
            mFile.DropDownItems.Add("Refresh download address...", null, delegate { RefreshSelectedUrl(); });
            mFile.DropDownItems.Add(new ToolStripSeparator());
            mFile.DropDownItems.Add("Remove", null, delegate { DeleteSelected(); });
            mFile.DropDownItems.Add("Properties", null, delegate { ShowSelectedProperties(); });

            ToolStripMenuItem mDownloads = new ToolStripMenuItem("Downloads");
            mDownloads.DropDownItems.Add("Resume All", null, delegate { ResumeAll(); });
            mDownloads.DropDownItems.Add("Stop All", null, delegate { PauseAll(); });
            mDownloads.DropDownItems.Add("Delete All Completed", null, delegate { DeleteCompleted(); });
            mDownloads.DropDownItems.Add(new ToolStripSeparator());
            mDownloads.DropDownItems.Add("Speed Limiter...", null, delegate { OpenSpeedLimitDialog(); });
            mDownloads.DropDownItems.Add("Scheduler...", null, delegate { OpenSchedulerDialog(); });
            mDownloads.DropDownItems.Add("Options...", null, delegate { OpenOptionsDialog(); });

            ToolStripMenuItem mView = new ToolStripMenuItem("View");
            ToolStripMenuItem mToggleTheme = new ToolStripMenuItem("Switch Classic Light / Dark Theme");
            mToggleTheme.Click += delegate
            {
                _darkTheme = !_darkTheme;
                ConfigureThemeColors();
                ApplyThemeToControls();
                SaveState();
            };
            ToolStripMenuItem mToggleTree = new ToolStripMenuItem("Show Categories Panel");
            mToggleTree.Checked = true;
            mToggleTree.CheckOnClick = true;
            mToggleTree.CheckedChanged += delegate
            {
                _splitMain.Panel1Collapsed = !mToggleTree.Checked;
            };
            ToolStripMenuItem mToggleViz = new ToolStripMenuItem("Show Segment & Speed Graph");
            mToggleViz.Checked = true;
            mToggleViz.CheckOnClick = true;
            mToggleViz.CheckedChanged += delegate
            {
                _vizPanel.Visible = mToggleViz.Checked;
            };
            mView.DropDownItems.Add(mToggleTheme);
            mView.DropDownItems.Add(new ToolStripSeparator());
            mView.DropDownItems.Add(mToggleTree);
            mView.DropDownItems.Add(mToggleViz);

            ToolStripMenuItem mHelp = new ToolStripMenuItem("Help");
            mHelp.DropDownItems.Add("Browser & YouTube Extension Setup...", null, delegate { OpenBrowserExtensionDialog(); });
            mHelp.DropDownItems.Add("Open Downloads Folder", null, delegate
            {
                Process.Start(new ProcessStartInfo(AppPaths.BaseDownloadDir) { UseShellExecute = true });
            });
            mHelp.DropDownItems.Add(new ToolStripSeparator());
            mHelp.DropDownItems.Add("About WinIDM", null, delegate
            {
                MessageBox.Show(this,
                    "WinIDM v3.4 — High-Speed Internet Download Manager\n\n" +
                    "• Up to 32 parallel connections with dynamic work-stealing\n" +
                    "• Lock-free direct NTFS disk I/O with 1 MB write coalescing\n" +
                    "• Built-in YouTube & HLS (.m3u8) adaptive video downloader\n" +
                    "• Chrome / Edge / Brave floating video download extension",
                    "About WinIDM", MessageBoxButtons.OK, MessageBoxIcon.Information);
            });

            _menuStrip.Items.AddRange(new ToolStripItem[] { mTasks, mFile, mDownloads, mView, mHelp });

            // 2. Classic IDM Graphical Toolbar (Large 32x32 Icons Above Text)
            _toolStrip = new ToolStrip();
            _toolStrip.Dock = DockStyle.Top;
            _toolStrip.GripStyle = ToolStripGripStyle.Hidden;
            _toolStrip.AutoSize = false;
            _toolStrip.Height = 64;
            _toolStrip.ImageScalingSize = new Size(30, 30);
            _toolStrip.Padding = new Padding(6, 4, 6, 4);

            AddIdmToolButton("Add URL", "add", delegate { OpenAddUrlDialog(""); });
            AddIdmToolButton("Resume", "resume", delegate { ResumeSelected(); });
            AddIdmToolButton("Stop", "pause", delegate { PauseSelected(); });
            AddIdmToolButton("Stop All", "stopall", delegate { PauseAll(); });
            AddIdmToolButton("Delete", "delete", delegate { DeleteSelected(); });
            AddIdmToolButton("Del Completed", "deldone", delegate { DeleteCompleted(); });
            _toolStrip.Items.Add(new ToolStripSeparator());
            AddIdmToolButton("Options", "options", delegate { OpenOptionsDialog(); });
            AddIdmToolButton("Scheduler", "scheduler", delegate { OpenSchedulerDialog(); });
            AddIdmToolButton("Start Queue", "resume", delegate { ResumeAll(); });
            _toolStrip.Items.Add(new ToolStripSeparator());
            AddIdmToolButton("Grabber", "grabber", delegate { OpenSiteGrabberDialog(); });
            AddIdmToolButton("Batch", "batch", delegate { OpenBatchDialog(); });
            AddIdmToolButton("Speed Limit", "speed", delegate { OpenSpeedLimitDialog(); });
            AddIdmToolButton("Browser Ext", "browser", delegate { OpenBrowserExtensionDialog(); });

            // 3. Bottom Status Bar
            _statusBar = new Panel();
            _statusBar.Dock = DockStyle.Bottom;
            _statusBar.Height = 26;
            _statusBar.Padding = new Padding(10, 4, 10, 3);

            _lblStatusLeft = new Label();
            _lblStatusLeft.Dock = DockStyle.Left;
            _lblStatusLeft.AutoSize = true;
            _lblStatusLeft.Text = "Ready";

            _lblStatusRight = new Label();
            _lblStatusRight.Dock = DockStyle.Right;
            _lblStatusRight.AutoSize = true;
            _lblStatusRight.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
            _lblStatusRight.Text = "Transfer Rate: 0 B/s";

            _statusBar.Controls.Add(_lblStatusRight);
            _statusBar.Controls.Add(_lblStatusLeft);

            // 4. Split Container: Left IDM Category Tree | Right Queue + Visualizer
            _splitMain = new SplitContainer();
            _splitMain.Dock = DockStyle.Fill;
            _splitMain.SplitterDistance = 205;
            _splitMain.SplitterWidth = 4;
            _splitMain.FixedPanel = FixedPanel.Panel1;

            _catImageList = new ImageList();
            _catImageList.ImageSize = new Size(16, 16);
            _catImageList.ColorDepth = ColorDepth.Depth32Bit;
            _catImageList.Images.Add("folder", IdmIconFactory.CreateCategoryIcon("folder"));
            _catImageList.Images.Add("compressed", IdmIconFactory.CreateCategoryIcon("compressed"));
            _catImageList.Images.Add("documents", IdmIconFactory.CreateCategoryIcon("documents"));
            _catImageList.Images.Add("music", IdmIconFactory.CreateCategoryIcon("music"));
            _catImageList.Images.Add("programs", IdmIconFactory.CreateCategoryIcon("programs"));
            _catImageList.Images.Add("video", IdmIconFactory.CreateCategoryIcon("video"));
            _catImageList.Images.Add("general", IdmIconFactory.CreateCategoryIcon("folder"));
            _catImageList.Images.Add("unfinished", IdmIconFactory.CreateCategoryIcon("unfinished"));
            _catImageList.Images.Add("finished", IdmIconFactory.CreateCategoryIcon("finished"));

            _treeCategories = new TreeView();
            _treeCategories.Dock = DockStyle.Fill;
            _treeCategories.BorderStyle = BorderStyle.None;
            _treeCategories.HideSelection = false;
            _treeCategories.FullRowSelect = true;
            _treeCategories.ItemHeight = 25;
            _treeCategories.ImageList = _catImageList;

            _nodeAll = new TreeNode("All Downloads", 0, 0);
            _nodeAll.Tag = "All Downloads";

            string[] subCats = { "Compressed", "Documents", "Music", "Programs", "Video", "General" };
            string[] subKeys = { "compressed", "documents", "music", "programs", "video", "general" };
            for (int i = 0; i < subCats.Length; i++)
            {
                int imgIdx = _catImageList.Images.IndexOfKey(subKeys[i]);
                TreeNode sub = new TreeNode(subCats[i], imgIdx, imgIdx);
                sub.Tag = subCats[i];
                _nodeAll.Nodes.Add(sub);
                _subCatNodes[subCats[i]] = sub;
            }

            _nodeUnfinished = new TreeNode("Unfinished", 7, 7);
            _nodeUnfinished.Tag = "Unfinished";

            _nodeFinished = new TreeNode("Finished", 8, 8);
            _nodeFinished.Tag = "Finished";

            _treeCategories.Nodes.Add(_nodeAll);
            _treeCategories.Nodes.Add(_nodeUnfinished);
            _treeCategories.Nodes.Add(_nodeFinished);
            _nodeAll.Expand();
            _treeCategories.SelectedNode = _nodeAll;

            _treeCategories.AfterSelect += delegate(object s, TreeViewEventArgs e)
            {
                if (e.Node != null && e.Node.Tag != null)
                {
                    _activeFilter = e.Node.Tag.ToString();
                    _listDownloads.Items.Clear();
                    RefreshListView();
                }
            };

            _splitMain.Panel1.Controls.Add(_treeCategories);

            // Right Side: Owner-Drawn IDM Queue ListView + Bottom Segment & Speed Monitor
            _vizPanel = new BufferedPanel();
            _vizPanel.Dock = DockStyle.Bottom;
            _vizPanel.Height = 84;
            _vizPanel.Paint += VizPanel_Paint;

            _listDownloads = new BufferedListView();
            _listDownloads.Dock = DockStyle.Fill;
            _listDownloads.View = View.Details;
            _listDownloads.FullRowSelect = true;
            _listDownloads.GridLines = true;
            _listDownloads.MultiSelect = false;
            _listDownloads.BorderStyle = BorderStyle.None;
            _listDownloads.OwnerDraw = true;

            // Set row height cleanly via small ImageList
            ImageList rowHeightHolder = new ImageList();
            rowHeightHolder.ImageSize = new Size(1, 24);
            _listDownloads.SmallImageList = rowHeightHolder;

            _listDownloads.Columns.Add("File Name", 275);
            _listDownloads.Columns.Add("Size", 90, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Status", 185);
            _listDownloads.Columns.Add("Time Left", 90, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Transfer Rate", 105, HorizontalAlignment.Right);
            _listDownloads.Columns.Add("Segments", 90, HorizontalAlignment.Center);
            _listDownloads.Columns.Add("Category", 88);
            _listDownloads.Columns.Add("URL", 210);

            _listDownloads.DrawColumnHeader += ListDownloads_DrawColumnHeader;
            _listDownloads.DrawItem += delegate(object s, DrawListViewItemEventArgs e) { e.DrawDefault = false; };
            _listDownloads.DrawSubItem += ListDownloads_DrawSubItem;

            _listDownloads.SelectedIndexChanged += delegate
            {
                if (_listDownloads.SelectedItems.Count > 0)
                {
                    _selectedTaskId = _listDownloads.SelectedItems[0].Tag as string;
                    _vizPanel.Invalidate();
                }
            };
            _listDownloads.DoubleClick += delegate { OpenSelectedFile(); };

            BuildContextMenu();
            _listDownloads.ContextMenuStrip = _listMenu;

            _splitMain.Panel2.Controls.Add(_listDownloads);
            _splitMain.Panel2.Controls.Add(_vizPanel);

            this.Controls.Add(_splitMain);
            this.Controls.Add(_statusBar);
            this.Controls.Add(_toolStrip);
            this.Controls.Add(_menuStrip);
            this.MainMenuStrip = _menuStrip;
        }

        private void AddIdmToolButton(string text, string iconKey, Action onClick)
        {
            ToolStripButton btn = new ToolStripButton();
            btn.Text = text;
            btn.Image = IdmIconFactory.CreateToolbarIcon(iconKey, 30);
            btn.DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
            btn.TextImageRelation = TextImageRelation.ImageAboveText;
            btn.ImageAlign = ContentAlignment.TopCenter;
            btn.TextAlign = ContentAlignment.BottomCenter;
            btn.AutoSize = false;
            btn.Width = 74;
            btn.Height = 54;
            btn.Font = new Font("Segoe UI", 8.2f, FontStyle.Regular);
            btn.Margin = new Padding(1, 0, 1, 0);
            btn.Click += delegate { onClick(); };
            _toolStrip.Items.Add(btn);
        }

        private void ApplyThemeToControls()
        {
            this.BackColor = ColWindowBg;
            this.ForeColor = ColTextPrimary;

            _menuStrip.BackColor = ColMenuBg;
            _menuStrip.ForeColor = ColTextPrimary;
            foreach (ToolStripMenuItem top in _menuStrip.Items)
            {
                top.ForeColor = ColTextPrimary;
            }

            _toolStrip.BackColor = ColToolbarBg;
            _toolStrip.ForeColor = ColTextPrimary;
            foreach (ToolStripItem item in _toolStrip.Items)
            {
                item.ForeColor = ColTextPrimary;
            }

            _treeCategories.BackColor = ColSidebarBg;
            _treeCategories.ForeColor = ColTextPrimary;

            _listDownloads.BackColor = ColListBg;
            _listDownloads.ForeColor = ColTextPrimary;

            _statusBar.BackColor = ColToolbarBg;
            _lblStatusLeft.ForeColor = ColTextMuted;
            _lblStatusRight.ForeColor = ColTextPrimary;

            _splitMain.BackColor = ColBorder;
            _listDownloads.Invalidate();
            _vizPanel.Invalidate();
        }

        private void ListDownloads_DrawColumnHeader(object sender, DrawListViewColumnHeaderEventArgs e)
        {
            using (Brush bg = new SolidBrush(ColHeaderBg))
            {
                e.Graphics.FillRectangle(bg, e.Bounds);
            }
            using (Pen border = new Pen(ColBorder))
            {
                e.Graphics.DrawLine(border, e.Bounds.Right - 1, e.Bounds.Top + 3, e.Bounds.Right - 1, e.Bounds.Bottom - 3);
                e.Graphics.DrawLine(border, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            }
            Rectangle txtRect = new Rectangle(e.Bounds.X + 6, e.Bounds.Y, Math.Max(1, e.Bounds.Width - 12), e.Bounds.Height);
            TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
            if (e.Header.TextAlign == HorizontalAlignment.Right) flags |= TextFormatFlags.Right;
            else if (e.Header.TextAlign == HorizontalAlignment.Center) flags |= TextFormatFlags.HorizontalCenter;
            else flags |= TextFormatFlags.Left;

            using (Font hdrFont = new Font("Segoe UI", 8.8f, FontStyle.Bold))
            {
                TextRenderer.DrawText(e.Graphics, e.Header.Text, hdrFont, txtRect, ColTextPrimary, flags);
            }
        }

        private void ListDownloads_DrawSubItem(object sender, DrawListViewSubItemEventArgs e)
        {
            bool selected = e.Item.Selected;
            Color rowBg = selected
                ? ColSelectionBg
                : ((e.ItemIndex % 2 == 1) ? ColListAltBg : ColListBg);
            Color txtColor = (selected && _darkTheme) ? Color.White : ColTextPrimary;

            using (Brush bg = new SolidBrush(rowBg))
            {
                e.Graphics.FillRectangle(bg, e.Bounds);
            }

            DownloadTask task = FindTaskById(e.Item.Tag as string);

            // Column 0: Category / File-Type Icon + File Name
            if (e.ColumnIndex == 0)
            {
                string catKey = (task != null && !string.IsNullOrEmpty(task.Category)) ? task.Category.ToLowerInvariant() : "general";
                int imgIdx = _catImageList.Images.IndexOfKey(catKey);
                if (imgIdx < 0) imgIdx = 0;

                int iconY = e.Bounds.Y + (e.Bounds.Height - 16) / 2;
                e.Graphics.DrawImage(_catImageList.Images[imgIdx], e.Bounds.X + 6, iconY, 16, 16);

                Rectangle txtRect = new Rectangle(e.Bounds.X + 26, e.Bounds.Y, Math.Max(1, e.Bounds.Width - 30), e.Bounds.Height);
                TextRenderer.DrawText(e.Graphics, e.SubItem.Text, this.Font, txtRect, txtColor,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                return;
            }

            // Column 2: IDM Signature Graphical Progress Bar + Status Text
            if (e.ColumnIndex == 2 && task != null)
            {
                Rectangle barOuter = new Rectangle(e.Bounds.X + 5, e.Bounds.Y + 4, Math.Max(10, e.Bounds.Width - 10), Math.Max(8, e.Bounds.Height - 8));
                Color trackBg = _darkTheme ? Color.FromArgb(30, 41, 59) : Color.FromArgb(234, 240, 248);

                using (Brush trackBr = new SolidBrush(trackBg))
                {
                    e.Graphics.FillRectangle(trackBr, barOuter);
                }

                double pct = task.GetProgressPercent();
                if (pct > 0.0)
                {
                    int fillW = Math.Max(2, (int)((barOuter.Width - 2) * (pct / 100.0)));
                    Rectangle barFill = new Rectangle(barOuter.X + 1, barOuter.Y + 1, fillW, Math.Max(4, barOuter.Height - 2));

                    Color cTop = ColProgressGreen;
                    Color cBot = Color.FromArgb(22, 163, 74);
                    if (task.Status == DownloadState.Error)
                    {
                        cTop = Color.FromArgb(248, 113, 113);
                        cBot = Color.FromArgb(220, 38, 38);
                    }
                    else if (task.Status == DownloadState.Paused)
                    {
                        cTop = Color.FromArgb(251, 191, 36);
                        cBot = Color.FromArgb(217, 119, 6);
                    }
                    else if (task.Status == DownloadState.Completed)
                    {
                        cTop = Color.FromArgb(59, 130, 246);
                        cBot = Color.FromArgb(29, 78, 216);
                    }

                    using (LinearGradientBrush fillBr = new LinearGradientBrush(barFill, cTop, cBot, 90f))
                    {
                        e.Graphics.FillRectangle(fillBr, barFill);
                    }
                }

                using (Pen borderPen = new Pen(ColBorder))
                {
                    e.Graphics.DrawRectangle(borderPen, barOuter);
                }

                Color labelColor = (pct > 45.0 || _darkTheme) ? Color.White : ColTextPrimary;
                using (Font stFont = new Font("Segoe UI", 8.2f, FontStyle.Bold))
                {
                    TextRenderer.DrawText(e.Graphics, e.SubItem.Text, stFont, barOuter, labelColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                }
                return;
            }

            // Standard Columns
            Rectangle rect = new Rectangle(e.Bounds.X + 6, e.Bounds.Y, Math.Max(1, e.Bounds.Width - 12), e.Bounds.Height);
            TextFormatFlags align = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
            if (e.ColumnIndex == 1 || e.ColumnIndex == 3 || e.ColumnIndex == 4) align |= TextFormatFlags.Right;
            else if (e.ColumnIndex == 5) align |= TextFormatFlags.HorizontalCenter;
            else align |= TextFormatFlags.Left;

            TextRenderer.DrawText(e.Graphics, e.SubItem.Text, this.Font, rect, txtColor, align);
        }

        private void BuildContextMenu()
        {
            _listMenu = new ContextMenuStrip();
            _listMenu.Items.Add("Open", null, delegate { OpenSelectedFile(); });
            _listMenu.Items.Add("Open Folder", null, delegate { OpenSelectedFolder(); });
            _listMenu.Items.Add(new ToolStripSeparator());
            _listMenu.Items.Add("Resume Download", null, delegate { ResumeSelected(); });
            _listMenu.Items.Add("Stop / Pause Download", null, delegate { PauseSelected(); });
            _listMenu.Items.Add("Refresh Download Address...", null, delegate { RefreshSelectedUrl(); });
            _listMenu.Items.Add("Copy Download URL", null, delegate
            {
                DownloadTask t = GetSelectedTask();
                if (t != null) Clipboard.SetText(t.Url);
            });
            _listMenu.Items.Add("Properties & SHA-256", null, delegate { ShowSelectedProperties(); });
            _listMenu.Items.Add(new ToolStripSeparator());
            _listMenu.Items.Add("Remove", null, delegate { DeleteSelected(); });
        }

        private void SetupTray()
        {
            _trayIcon = new NotifyIcon();
            _trayIcon.Icon = this.Icon;
            _trayIcon.Text = "Internet Download Manager (WinIDM)";
            _trayIcon.Visible = true;
            _trayIcon.MouseClick += delegate(object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left) RestoreFromTray();
            };
            _trayIcon.DoubleClick += delegate { RestoreFromTray(); };

            ContextMenuStrip trayMenu = new ContextMenuStrip();
            trayMenu.Items.Add("Open WinIDM", null, delegate { RestoreFromTray(); });
            trayMenu.Items.Add("Add New Download...", null, delegate { RestoreFromTray(); OpenAddUrlDialog(""); });
            trayMenu.Items.Add("Stop All Downloads", null, delegate { PauseAll(); });
            trayMenu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem clipItem = new ToolStripMenuItem("Auto-Catch Copied Download Links");
            clipItem.CheckOnClick = true;
            clipItem.Checked = _clipboardMonitor;
            clipItem.CheckedChanged += delegate { _clipboardMonitor = clipItem.Checked; SaveState(); };
            trayMenu.Items.Add(clipItem);

            ToolStripMenuItem startItem = new ToolStripMenuItem("Start Automatically with Windows");
            startItem.CheckOnClick = true;
            startItem.Checked = AppPaths.IsStartupEnabled();
            startItem.CheckedChanged += delegate { AppPaths.SetStartupEnabled(startItem.Checked); };
            trayMenu.Items.Add(startItem);

            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("Exit", null, delegate
            {
                _forceExit = true;
                this.Close();
            });

            _trayIcon.ContextMenuStrip = trayMenu;
        }

        private void RestoreFromTray()
        {
            this.ShowInTaskbar = true;
            this.Show();
            if (this.WindowState == FormWindowState.Minimized)
            {
                this.WindowState = FormWindowState.Normal;
            }
            this.Activate();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!_forceExit && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                SaveState();
                this.Hide();
                _trayIcon.ShowBalloonTip(2500, "WinIDM is running in the background",
                    "Browser capture & scheduler remain active. Click the tray icon to reopen.", ToolTipIcon.Info);
                return;
            }

            if (_uiTimer != null) _uiTimer.Stop();
            for (int i = 0; i < _tasks.Count; i++) _tasks[i].Pause();
            SaveState();
            if (_bridge != null) _bridge.Stop();
            if (_trayIcon != null) _trayIcon.Visible = false;
            base.OnFormClosing(e);
        }

        // ====================================================================
        // CORE QUEUE OPERATIONS
        // ====================================================================
        public void AddDownload(string url, string fileName, string saveDir, int threads, Dictionary<string, string> headers, bool startNow)
        {
            string cleanUrl = (url ?? "").Trim();
            if (!cleanUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                !cleanUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            DownloadTask task = new DownloadTask();
            task.Id = DateTime.UtcNow.Ticks.ToString() + "_" + _tasks.Count;
            task.Url = cleanUrl;
            task.IsStreamPage = DownloadTask.IsVideoPageUrl(cleanUrl);
            task.FileName = string.IsNullOrWhiteSpace(fileName) ? "" : AppPaths.SanitizeFileName(fileName);
            task.SaveDir = string.IsNullOrWhiteSpace(saveDir) ? "" : saveDir.Trim();
            task.NumThreads = Math.Max(1, Math.Min(32, threads > 0 ? threads : _defaultThreads));
            task.ComputeSha256 = _verifySha256;
            if (task.IsStreamPage) task.Category = "Video";
            if (headers != null)
            {
                foreach (KeyValuePair<string, string> kv in headers)
                {
                    task.CustomHeaders[kv.Key] = kv.Value;
                }
            }
            task.Status = startNow ? DownloadState.Queued : DownloadState.Paused;

            _tasks.Add(task);
            _selectedTaskId = task.Id;
            UpdateTreeCounts();
            RefreshListView();
            SaveState();
            DispatchQueue();
        }

        private void DispatchQueue()
        {
            int active = 0;
            for (int i = 0; i < _tasks.Count; i++)
            {
                DownloadState st = _tasks[i].Status;
                if (st == DownloadState.Downloading || st == DownloadState.Connecting || st == DownloadState.Finalizing)
                {
                    active++;
                }
            }
            for (int i = 0; i < _tasks.Count; i++)
            {
                if (active >= _maxConcurrent) break;
                if (_tasks[i].Status == DownloadState.Queued)
                {
                    _tasks[i].Start(_limiter, delegate
                    {
                        if (this.IsHandleCreated)
                        {
                            this.BeginInvoke((Action)delegate
                            {
                                UpdateTreeCounts();
                                RefreshListView();
                            });
                        }
                    });
                    active++;
                }
            }
        }

        private void UpdateTreeCounts()
        {
            if (_nodeAll == null) return;
            int total = _tasks.Count;
            int unfinished = 0;
            int finished = 0;
            Dictionary<string, int> catCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < _tasks.Count; i++)
            {
                DownloadTask t = _tasks[i];
                if (t.Status == DownloadState.Completed) finished++;
                else unfinished++;

                string cat = string.IsNullOrEmpty(t.Category) ? "General" : t.Category;
                int cur;
                catCounts.TryGetValue(cat, out cur);
                catCounts[cat] = cur + 1;
            }

            string allTxt = string.Format("All Downloads ({0})", total);
            if (_nodeAll.Text != allTxt) _nodeAll.Text = allTxt;

            string unfTxt = string.Format("Unfinished ({0})", unfinished);
            if (_nodeUnfinished.Text != unfTxt) _nodeUnfinished.Text = unfTxt;

            string finTxt = string.Format("Finished ({0})", finished);
            if (_nodeFinished.Text != finTxt) _nodeFinished.Text = finTxt;

            foreach (KeyValuePair<string, TreeNode> kv in _subCatNodes)
            {
                int c;
                catCounts.TryGetValue(kv.Key, out c);
                string label = c > 0 ? string.Format("{0} ({1})", kv.Key, c) : kv.Key;
                if (kv.Value.Text != label) kv.Value.Text = label;
            }
        }

        private List<DownloadTask> GetFilteredTasks()
        {
            List<DownloadTask> list = new List<DownloadTask>();
            for (int i = 0; i < _tasks.Count; i++)
            {
                DownloadTask t = _tasks[i];
                if (_activeFilter == "All Downloads") list.Add(t);
                else if (_activeFilter == "Unfinished" && t.Status != DownloadState.Completed) list.Add(t);
                else if (_activeFilter == "Finished" && t.Status == DownloadState.Completed) list.Add(t);
                else if (string.Equals(t.Category, _activeFilter, StringComparison.OrdinalIgnoreCase)) list.Add(t);
            }
            return list;
        }

        private DownloadTask FindTaskById(string id)
        {
            if (string.IsNullOrEmpty(id)) return null;
            for (int i = 0; i < _tasks.Count; i++)
            {
                if (_tasks[i].Id == id) return _tasks[i];
            }
            return null;
        }

        private DownloadTask GetSelectedTask()
        {
            return FindTaskById(_selectedTaskId);
        }

        private void RefreshListView()
        {
            List<DownloadTask> visible = GetFilteredTasks();
            if (_listDownloads.Items.Count != visible.Count)
            {
                _listDownloads.BeginUpdate();
                _listDownloads.Items.Clear();
                for (int i = 0; i < visible.Count; i++)
                {
                    ListViewItem item = new ListViewItem(visible[i].FileName.Length > 0 ? visible[i].FileName : visible[i].Url);
                    item.Tag = visible[i].Id;
                    for (int c = 1; c < 8; c++) item.SubItems.Add("");
                    _listDownloads.Items.Add(item);
                }
                _listDownloads.EndUpdate();
            }

            bool changed = false;
            for (int i = 0; i < visible.Count; i++)
            {
                DownloadTask t = visible[i];
                ListViewItem row = _listDownloads.Items[i];
                row.Tag = t.Id;

                string name = string.IsNullOrEmpty(t.FileName) ? t.Url : t.FileName;
                long dl = t.GetDownloadedBytes();
                string sizeStr = (t.TotalSize > 0) ? AppPaths.FormatBytes(t.TotalSize) : (dl > 0 ? AppPaths.FormatBytes(dl) : "Unknown");

                string statusBarText;
                if (t.Status == DownloadState.Completed)
                {
                    statusBarText = "Complete (100%)";
                }
                else if (t.Status == DownloadState.Error)
                {
                    statusBarText = string.IsNullOrEmpty(t.ErrorMessage) ? "Error" : ("Error: " + t.ErrorMessage);
                }
                else if (t.Status == DownloadState.Downloading)
                {
                    statusBarText = string.Format("Downloading  {0:0.0}%", t.GetProgressPercent());
                }
                else if (t.Status == DownloadState.Paused)
                {
                    statusBarText = string.Format("Paused  ({0:0.0}%)", t.GetProgressPercent());
                }
                else
                {
                    statusBarText = t.Status.ToString();
                }

                string etaStr = (t.Status == DownloadState.Downloading) ? AppPaths.FormatDuration(t.EtaSeconds) : "";
                string spdStr = (t.Status == DownloadState.Downloading && t.SpeedBps > 0) ? (AppPaths.FormatBytes(t.SpeedBps) + "/s") : "";
                string segStr = t.IsStreamPage ? "Adaptive HD" : (t.Segments.Count + (t.DirectWrite ? " Conn" : ""));
                string catStr = string.IsNullOrEmpty(t.Category) ? "General" : t.Category;

                if (row.SubItems[0].Text != name) { row.SubItems[0].Text = name; changed = true; }
                if (row.SubItems[1].Text != sizeStr) { row.SubItems[1].Text = sizeStr; changed = true; }
                if (row.SubItems[2].Text != statusBarText) { row.SubItems[2].Text = statusBarText; changed = true; }
                if (row.SubItems[3].Text != etaStr) { row.SubItems[3].Text = etaStr; changed = true; }
                if (row.SubItems[4].Text != spdStr) { row.SubItems[4].Text = spdStr; changed = true; }
                if (row.SubItems[5].Text != segStr) { row.SubItems[5].Text = segStr; changed = true; }
                if (row.SubItems[6].Text != catStr) { row.SubItems[6].Text = catStr; changed = true; }
                if (row.SubItems[7].Text != t.Url) { row.SubItems[7].Text = t.Url; changed = true; }
            }

            if (changed)
            {
                _listDownloads.Invalidate();
            }
        }

        private void UiTimer_Tick(object sender, EventArgs e)
        {
            if (_clipboardMonitor)
            {
                try
                {
                    if (Clipboard.ContainsText())
                    {
                        string clip = Clipboard.GetText().Trim();
                        if (clip != _lastClipboard &&
                            (clip.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                             clip.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) &&
                            !clip.Contains(" ") &&
                            (AppPaths.DetectCategory(clip) != "General" || DownloadTask.IsVideoPageUrl(clip)))
                        {
                            _lastClipboard = clip;
                            AddDownload(clip, "", "", _defaultThreads, null, true);
                        }
                    }
                }
                catch { }
            }

            if (_schedulerEnabled)
            {
                DateTime now = DateTime.Now;
                if (now.Hour == _schedHour && now.Minute == _schedMin && now.Second == 0)
                {
                    ResumeAll();
                }
            }

            double totalSpeed = 0.0;
            int activeCount = 0;
            bool newlyCompleted = false;

            for (int i = 0; i < _tasks.Count; i++)
            {
                DownloadTask t = _tasks[i];
                t.UpdateMetrics(0.25);
                if (t.Status == DownloadState.Downloading)
                {
                    totalSpeed += t.SpeedBps;
                    activeCount++;
                }
                else if (t.Status == DownloadState.Completed && !_notifiedIds.Contains(t.Id))
                {
                    _notifiedIds.Add(t.Id);
                    newlyCompleted = true;
                    _trayIcon.ShowBalloonTip(2500, "Download Complete",
                        t.FileName + " (" + AppPaths.FormatBytes(t.GetDownloadedBytes()) + ")", ToolTipIcon.Info);
                }
            }

            _tickCount++;
            if (newlyCompleted || (activeCount > 0 && (_tickCount % 20 == 0)))
            {
                UpdateTreeCounts();
                SaveState();
            }

            DispatchQueue();
            RefreshListView();

            _speedHistory.Dequeue();
            _speedHistory.Enqueue(totalSpeed);
            _vizPanel.Invalidate();

            double lim = _limiter.GetLimitKbps();
            _lblStatusLeft.Text = string.Format("Downloads: {0}  |  Active: {1}  |  Browser & YouTube Catcher: Ready", _tasks.Count, activeCount);
            _lblStatusRight.Text = string.Format("Speed Limiter: {0}  |  Transfer Rate: {1}/s",
                lim <= 0 ? "Off" : (lim.ToString("0") + " KB/s"),
                AppPaths.FormatBytes(totalSpeed));
        }

        private void VizPanel_Paint(object sender, PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int w = _vizPanel.Width;
            int h = _vizPanel.Height;

            using (Brush panelBr = new SolidBrush(ColToolbarBg))
            {
                g.FillRectangle(panelBr, 0, 0, w, h);
            }
            using (Pen topBorder = new Pen(ColBorder))
            {
                g.DrawLine(topBorder, 0, 0, w, 0);
            }

            int sparkW = 240;
            int segAreaW = Math.Max(140, w - sparkW - 24);

            DownloadTask task = GetSelectedTask();
            if (task == null && _tasks.Count > 0) task = _tasks[_tasks.Count - 1];

            using (Brush txtBrush = new SolidBrush(ColTextPrimary))
            using (Brush mutedBrush = new SolidBrush(ColTextMuted))
            using (Font boldFont = new Font("Segoe UI", 8.8f, FontStyle.Bold))
            {
                if (task != null)
                {
                    string prefix = task.IsStreamPage ? "Adaptive Stream: " : "Start positions & download progress by connections: ";
                    string title = prefix + (string.IsNullOrEmpty(task.FileName) ? task.Url : task.FileName);
                    g.DrawString(title, boldFont, txtBrush, new RectangleF(10, 7, segAreaW - 10, 20));

                    Color slotColor = _darkTheme ? Color.FromArgb(15, 23, 42) : Color.White;
                    Rectangle segFrame = new Rectangle(10, 30, segAreaW - 12, h - 40);

                    if (task.IsStreamPage)
                    {
                        using (Brush brSlot = new SolidBrush(slotColor))
                        using (Brush brFill = new SolidBrush(task.Status == DownloadState.Error ? Color.FromArgb(220, 38, 38) : ColProgressGreen))
                        {
                            g.FillRectangle(brSlot, segFrame);
                            double ratio = task.GetProgressPercent() / 100.0;
                            if (ratio > 0)
                            {
                                g.FillRectangle(brFill, segFrame.X, segFrame.Y, Math.Max(2f, (float)(segFrame.Width * ratio)), segFrame.Height);
                            }
                        }
                        using (Pen p = new Pen(ColBorder)) g.DrawRectangle(p, segFrame);
                    }
                    else
                    {
                        lock (task.SyncLock)
                        {
                            int n = task.Segments.Count;
                            if (n > 0)
                            {
                                float segW = (float)segFrame.Width / n;
                                using (Brush brSlot = new SolidBrush(slotColor))
                                using (Brush brDone = new SolidBrush(Color.FromArgb(37, 99, 235)))
                                using (Brush brAct = new SolidBrush(ColProgressGreen))
                                using (Brush brErr = new SolidBrush(Color.FromArgb(220, 38, 38)))
                                using (Pen slotPen = new Pen(ColBorder))
                                {
                                    for (int i = 0; i < n; i++)
                                    {
                                        DownloadSegment s = task.Segments[i];
                                        float x0 = segFrame.X + i * segW;
                                        float bw = Math.Max(2f, segW - (n > 24 ? 1f : 2f));
                                        g.FillRectangle(brSlot, x0, segFrame.Y, bw, segFrame.Height);

                                        double ratio = 0.0;
                                        if (s.Done || task.Status == DownloadState.Completed) ratio = 1.0;
                                        else if (task.IsHls) ratio = s.Downloaded > 0 ? 0.5 : 0.0;
                                        else
                                        {
                                            long segTot = (s.End >= 0) ? (s.End - s.Start + 1) : Math.Max(1L, task.TotalSize);
                                            long doneB = Math.Max(0L, s.Current - s.Start);
                                            ratio = Math.Min(1.0, (double)doneB / Math.Max(1L, segTot));
                                        }

                                        if (ratio > 0)
                                        {
                                            Brush fillBr = (task.Status == DownloadState.Error) ? brErr :
                                                           ((s.Done || task.Status == DownloadState.Completed) ? brDone : brAct);
                                            g.FillRectangle(fillBr, x0, segFrame.Y, Math.Max(2f, (float)(bw * ratio)), segFrame.Height);
                                        }
                                        if (n <= 32)
                                        {
                                            g.DrawRectangle(slotPen, x0, segFrame.Y, bw, segFrame.Height);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                else
                {
                    g.DrawString("Click 'Add URL' on the IDM toolbar, drop a link here, or click 'Download' on any web video.",
                        this.Font, mutedBrush, new RectangleF(10, 30, segAreaW - 10, 24));
                }

                // Right Throughput Sparkline Box
                int sx = segAreaW + 14;
                int sw = sparkW;
                Rectangle sparkRect = new Rectangle(sx, 8, sw, h - 16);
                Color sparkBgCol = _darkTheme ? Color.FromArgb(15, 23, 42) : Color.White;
                using (Brush sparkBg = new SolidBrush(sparkBgCol))
                using (Pen sparkBorder = new Pen(ColBorder))
                {
                    g.FillRectangle(sparkBg, sparkRect);
                    g.DrawRectangle(sparkBorder, sparkRect);
                }

                double[] samples = _speedHistory.ToArray();
                double peak = 0.0;
                for (int i = 0; i < samples.Length; i++) peak = Math.Max(peak, samples[i]);

                g.DrawString("Peak Speed: " + AppPaths.FormatBytes(peak) + "/s", boldFont, txtBrush, sx + 8, 11);

                if (peak > 0.0 && samples.Length > 1)
                {
                    PointF[] pts = new PointF[samples.Length];
                    float innerW = sw - 12;
                    float innerH = h - 44;
                    for (int i = 0; i < samples.Length; i++)
                    {
                        float px = sx + 6 + (innerW * i) / (samples.Length - 1);
                        float py = (h - 12) - (float)((samples[i] / peak) * innerH);
                        pts[i] = new PointF(px, py);
                    }
                    using (Pen linePen = new Pen(ColProgressGreen, 2f))
                    {
                        g.DrawLines(linePen, pts);
                    }
                }
            }
        }

        private void MainForm_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.Text))
            {
                string txt = e.Data.GetData(DataFormats.Text) as string;
                if (!string.IsNullOrWhiteSpace(txt))
                {
                    AddDownload(txt.Trim(), "", "", _defaultThreads, null, true);
                }
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files != null)
                {
                    for (int i = 0; i < files.Length; i++)
                    {
                        try
                        {
                            string[] lines = File.ReadAllLines(files[i]);
                            for (int l = 0; l < lines.Length; l++)
                            {
                                string line = lines[l].Trim();
                                if (line.StartsWith("URL=", StringComparison.OrdinalIgnoreCase)) line = line.Substring(4);
                                if (line.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                                    line.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                                {
                                    AddDownload(line, "", "", _defaultThreads, null, true);
                                    break;
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
        }

        // ====================================================================
        // TOOLBAR & CONTEXT MENU ACTIONS
        // ====================================================================
        private void ResumeSelected()
        {
            DownloadTask t = GetSelectedTask();
            if (t != null && t.Status != DownloadState.Completed)
            {
                t.Status = DownloadState.Queued;
                DispatchQueue();
                SaveState();
            }
        }

        private void ResumeAll()
        {
            for (int i = 0; i < _tasks.Count; i++)
            {
                if (_tasks[i].Status == DownloadState.Paused || _tasks[i].Status == DownloadState.Error)
                {
                    _tasks[i].Status = DownloadState.Queued;
                }
            }
            DispatchQueue();
            SaveState();
        }

        private void PauseSelected()
        {
            DownloadTask t = GetSelectedTask();
            if (t != null)
            {
                t.Pause();
                SaveState();
            }
        }

        private void PauseAll()
        {
            for (int i = 0; i < _tasks.Count; i++) _tasks[i].Pause();
            SaveState();
        }

        private void DeleteSelected()
        {
            DownloadTask t = GetSelectedTask();
            if (t != null)
            {
                t.Cancel();
                _tasks.Remove(t);
                _selectedTaskId = null;
                _listDownloads.Items.Clear();
                UpdateTreeCounts();
                RefreshListView();
                SaveState();
            }
        }

        private void DeleteCompleted()
        {
            int removed = 0;
            for (int i = _tasks.Count - 1; i >= 0; i--)
            {
                if (_tasks[i].Status == DownloadState.Completed)
                {
                    _tasks.RemoveAt(i);
                    removed++;
                }
            }
            if (removed > 0)
            {
                _selectedTaskId = null;
                _listDownloads.Items.Clear();
                UpdateTreeCounts();
                RefreshListView();
                SaveState();
            }
        }

        private void OpenSelectedFile()
        {
            DownloadTask t = GetSelectedTask();
            if (t != null && File.Exists(t.FullFilePath))
            {
                Process.Start(new ProcessStartInfo(t.FullFilePath) { UseShellExecute = true });
            }
        }

        private void OpenSelectedFolder()
        {
            DownloadTask t = GetSelectedTask();
            if (t == null) return;
            if (File.Exists(t.FullFilePath))
            {
                Process.Start("explorer.exe", "/select,\"" + t.FullFilePath + "\"");
            }
            else if (!string.IsNullOrEmpty(t.SaveDir) && Directory.Exists(t.SaveDir))
            {
                Process.Start(new ProcessStartInfo(t.SaveDir) { UseShellExecute = true });
            }
        }

        private void RefreshSelectedUrl()
        {
            DownloadTask t = GetSelectedTask();
            if (t == null) return;
            string nextUrl = PromptText("Refresh Download Address", "Paste new CDN URL (resumes from existing byte offsets):", t.Url);
            if (!string.IsNullOrWhiteSpace(nextUrl) && nextUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                t.Pause();
                t.Url = nextUrl.Trim();
                t.ErrorMessage = "";
                t.Status = DownloadState.Queued;
                DispatchQueue();
                SaveState();
            }
        }

        private void ShowSelectedProperties()
        {
            DownloadTask t = GetSelectedTask();
            if (t == null) return;
            string info = string.Format(
                "File Name: {0}\nURL: {1}\nSave Location: {2}\nTotal Size: {3}\nDownloaded: {4}\nSHA-256: {5}",
                t.FileName, t.Url, t.FullFilePath,
                AppPaths.FormatBytes(t.TotalSize),
                AppPaths.FormatBytes(t.GetDownloadedBytes()),
                string.IsNullOrEmpty(t.Sha256Hash) ? "(Pending or disabled)" : t.Sha256Hash);
            MessageBox.Show(this, info, "Download Properties", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void OpenAddUrlDialog(string prefill)
        {
            Form dlg = new Form();
            dlg.Text = "Enter new address to download";
            dlg.Size = new Size(540, 290);
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false;
            dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.BackColor = ColToolbarBg;
            dlg.ForeColor = ColTextPrimary;
            dlg.Font = this.Font;

            Label l1 = new Label { Text = "Address (Direct File, YouTube Video, or .m3u8 Stream):", Left = 16, Top = 14, Width = 490 };
            TextBox tbUrl = new TextBox { Text = string.IsNullOrEmpty(prefill) ? "https://" : prefill, Left = 16, Top = 36, Width = 490, BackColor = ColListBg, ForeColor = ColTextPrimary };

            Label l2 = new Label { Text = "Save As File Name (Optional - leave blank to auto-detect):", Left = 16, Top = 72, Width = 490 };
            TextBox tbName = new TextBox { Left = 16, Top = 94, Width = 490, BackColor = ColListBg, ForeColor = ColTextPrimary };

            Label l3 = new Label { Text = "Optional Header (e.g. Referer: https://site.com):", Left = 16, Top = 130, Width = 360 };
            TextBox tbHdr = new TextBox { Left = 16, Top = 152, Width = 360, BackColor = ColListBg, ForeColor = ColTextPrimary };

            Label l4 = new Label { Text = "Connections (1-32):", Left = 392, Top = 130, Width = 114 };
            NumericUpDown nudThr = new NumericUpDown { Left = 392, Top = 152, Width = 114, Minimum = 1, Maximum = 32, Value = _defaultThreads, BackColor = ColListBg, ForeColor = ColTextPrimary };

            Button btnNow = new Button { Text = "Start Download", Left = 276, Top = 200, Width = 115, Height = 32, FlatStyle = FlatStyle.Flat, BackColor = ColAccentBlue, ForeColor = Color.White };
            Button btnLater = new Button { Text = "Download Later", Left = 398, Top = 200, Width = 108, Height = 32, FlatStyle = FlatStyle.Flat, BackColor = ColHeaderBg, ForeColor = ColTextPrimary };

            bool startNow = true;
            btnNow.Click += delegate { startNow = true; dlg.DialogResult = DialogResult.OK; dlg.Close(); };
            btnLater.Click += delegate { startNow = false; dlg.DialogResult = DialogResult.OK; dlg.Close(); };

            dlg.Controls.AddRange(new Control[] { l1, tbUrl, l2, tbName, l3, tbHdr, l4, nudThr, btnNow, btnLater });
            dlg.AcceptButton = btnNow;

            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                Dictionary<string, string> hdrs = new Dictionary<string, string>();
                string rawH = tbHdr.Text.Trim();
                int colon = rawH.IndexOf(':');
                if (colon > 0)
                {
                    hdrs[rawH.Substring(0, colon).Trim()] = rawH.Substring(colon + 1).Trim();
                }
                AddDownload(tbUrl.Text, tbName.Text, "", (int)nudThr.Value, hdrs, startNow);
            }
        }

        private void OpenBatchDialog()
        {
            string pattern = PromptText("Add batch download",
                "Enter URL pattern with [01-20] wildcard (e.g. https://site.com/file_[01-10].zip):",
                "https://example.com/archive_[01-05].zip");
            if (string.IsNullOrWhiteSpace(pattern)) return;

            Match m = Regex.Match(pattern.Trim(), @"\[(\d+)-(\d+)\]");
            if (m.Success)
            {
                string s1 = m.Groups[1].Value;
                string s2 = m.Groups[2].Value;
                int start = int.Parse(s1);
                int end = int.Parse(s2);
                int pad = s1.Length;
                int step = (start <= end) ? 1 : -1;
                int count = 0;

                for (int v = start; (step > 0 ? v <= end : v >= end) && count < 200; v += step, count++)
                {
                    string num = v.ToString().PadLeft(pad, '0');
                    string expanded = pattern.Substring(0, m.Index) + num + pattern.Substring(m.Index + m.Length);
                    AddDownload(expanded, "", "", _defaultThreads, null, true);
                }
            }
            else if (pattern.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                AddDownload(pattern, "", "", _defaultThreads, null, true);
            }
        }

        private void OpenSiteGrabberDialog()
        {
            string pageUrl = PromptText("IDM Site Grabber",
                "Enter webpage URL to extract downloadable media & archive links:", "https://");
            if (string.IsNullOrWhiteSpace(pageUrl) || !pageUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase)) return;

            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(pageUrl.Trim());
                req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WinIDM/3.4";
                req.Timeout = 15000;
                string html;
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    html = sr.ReadToEnd();
                }

                HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                List<string> found = new List<string>();
                Uri baseUri = new Uri(pageUrl.Trim());

                foreach (Match m in Regex.Matches(html, @"(?:href|src)\s*=\s*[""']([^""'#]+)[""']", RegexOptions.IgnoreCase))
                {
                    Uri resolved;
                    if (Uri.TryCreate(baseUri, m.Groups[1].Value.Trim(), out resolved))
                    {
                        string abs = resolved.ToString();
                        if (abs.StartsWith("http", StringComparison.OrdinalIgnoreCase) &&
                            AppPaths.DetectCategory(abs) != "General" &&
                            !seen.Contains(abs))
                        {
                            seen.Add(abs);
                            found.Add(abs);
                        }
                    }
                }

                if (found.Count == 0)
                {
                    MessageBox.Show(this, "No downloadable media, archive, or program links found on that page.", "Site Grabber", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                if (MessageBox.Show(this,
                    string.Format("Found {0} downloadable files on that page.\nStart downloading all of them now?", found.Count),
                    "IDM Site Grabber", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    Dictionary<string, string> hdr = new Dictionary<string, string> { { "Referer", pageUrl.Trim() } };
                    for (int i = 0; i < found.Count; i++)
                    {
                        AddDownload(found[i], "", "", _defaultThreads, hdr, true);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not scan page: " + ex.Message, "Site Grabber Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void OpenSpeedLimitDialog()
        {
            string val = PromptText("Speed Limiter Settings",
                "Enter maximum download speed in KB/s (enter 0 for Unlimited):",
                ((int)_limiter.GetLimitKbps()).ToString());
            int kbps;
            if (!string.IsNullOrWhiteSpace(val) && int.TryParse(val.Trim(), out kbps))
            {
                _limiter.SetLimitKbps(Math.Max(0, kbps));
                SaveState();
            }
        }

        private void OpenSchedulerDialog()
        {
            string val = PromptText("IDM Scheduler",
                "Enter daily start hour (0-23) to auto-start queued downloads (or -1 to disable):",
                _schedulerEnabled ? _schedHour.ToString() : "-1");
            int hr;
            if (!string.IsNullOrWhiteSpace(val) && int.TryParse(val.Trim(), out hr))
            {
                if (hr >= 0 && hr <= 23)
                {
                    _schedulerEnabled = true;
                    _schedHour = hr;
                    _schedMin = 0;
                }
                else
                {
                    _schedulerEnabled = false;
                }
            }
        }

        private void OpenBrowserExtensionDialog()
        {
            string extDir = AppPaths.GenerateBrowserExtension();
            string msg =
                "Chrome / Edge / Brave Browser Integration Module is ready at:\n\n" +
                extDir + "\n\n" +
                "1. Open chrome://extensions or edge://extensions\n" +
                "2. Turn ON 'Developer mode' (top-right)\n" +
                "3. Click 'Load unpacked' (or Reload ↻) and select the folder above.\n\n" +
                "Open this folder now?";
            if (MessageBox.Show(this, msg, "IDM Browser Integration", MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
            {
                Process.Start(new ProcessStartInfo(extDir) { UseShellExecute = true });
            }
        }

        private void OpenOptionsDialog()
        {
            Form dlg = new Form();
            dlg.Text = "Internet Download Manager Configuration";
            dlg.Size = new Size(450, 295);
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false;
            dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.BackColor = ColToolbarBg;
            dlg.ForeColor = ColTextPrimary;
            dlg.Font = this.Font;

            Label l1 = new Label { Text = "Default max connection number (1-32):", Left = 18, Top = 20, Width = 250 };
            NumericUpDown nudThr = new NumericUpDown { Left = 290, Top = 18, Width = 120, Minimum = 1, Maximum = 32, Value = _defaultThreads, BackColor = ColListBg, ForeColor = ColTextPrimary };

            Label l2 = new Label { Text = "Max simultaneous downloads (1-10):", Left = 18, Top = 56, Width = 250 };
            NumericUpDown nudConc = new NumericUpDown { Left = 290, Top = 54, Width = 120, Minimum = 1, Maximum = 10, Value = _maxConcurrent, BackColor = ColListBg, ForeColor = ColTextPrimary };

            CheckBox chkSha = new CheckBox { Text = "Verify SHA-256 checksum on completion", Left = 18, Top = 96, Width = 390, Checked = _verifySha256 };
            CheckBox chkClip = new CheckBox { Text = "Auto-catch copied download & YouTube links from clipboard", Left = 18, Top = 126, Width = 390, Checked = _clipboardMonitor };
            CheckBox chkStart = new CheckBox { Text = "Launch WinIDM on Windows startup", Left = 18, Top = 156, Width = 390, Checked = AppPaths.IsStartupEnabled() };
            CheckBox chkDark = new CheckBox { Text = "Use Midnight Dark Theme (uncheck for Classic IDM Light)", Left = 18, Top = 186, Width = 390, Checked = _darkTheme };

            Button btnSave = new Button { Text = "OK", Left = 295, Top = 222, Width = 115, Height = 30, FlatStyle = FlatStyle.Flat, BackColor = ColAccentBlue, ForeColor = Color.White };
            btnSave.Click += delegate
            {
                _defaultThreads = (int)nudThr.Value;
                _maxConcurrent = (int)nudConc.Value;
                _verifySha256 = chkSha.Checked;
                _clipboardMonitor = chkClip.Checked;
                AppPaths.SetStartupEnabled(chkStart.Checked);
                if (_darkTheme != chkDark.Checked)
                {
                    _darkTheme = chkDark.Checked;
                    ConfigureThemeColors();
                    ApplyThemeToControls();
                }
                SaveState();
                dlg.Close();
            };

            dlg.Controls.AddRange(new Control[] { l1, nudThr, l2, nudConc, chkSha, chkClip, chkStart, chkDark, btnSave });
            dlg.ShowDialog(this);
        }

        private string PromptText(string title, string prompt, string defaultValue)
        {
            Form dlg = new Form();
            dlg.Text = title;
            dlg.Size = new Size(490, 175);
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false;
            dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.BackColor = ColToolbarBg;
            dlg.ForeColor = ColTextPrimary;
            dlg.Font = this.Font;

            Label lbl = new Label { Text = prompt, Left = 16, Top = 14, Width = 442 };
            TextBox tb = new TextBox { Text = defaultValue, Left = 16, Top = 42, Width = 442, BackColor = ColListBg, ForeColor = ColTextPrimary };
            Button ok = new Button { Text = "OK", Left = 266, Top = 86, Width = 92, Height = 30, DialogResult = DialogResult.OK, FlatStyle = FlatStyle.Flat, BackColor = ColAccentBlue, ForeColor = Color.White };
            Button cancel = new Button { Text = "Cancel", Left = 366, Top = 86, Width = 92, Height = 30, DialogResult = DialogResult.Cancel, FlatStyle = FlatStyle.Flat, BackColor = ColHeaderBg, ForeColor = ColTextPrimary };

            dlg.Controls.AddRange(new Control[] { lbl, tb, ok, cancel });
            dlg.AcceptButton = ok;
            dlg.CancelButton = cancel;
            return (dlg.ShowDialog(this) == DialogResult.OK) ? tb.Text : null;
        }

        // ====================================================================
        // CRASH-SAFE PERSISTENT QUEUE STORAGE
        // ====================================================================
        private void SaveState()
        {
            try
            {
                string dbPath = Path.Combine(AppPaths.BaseDownloadDir, "winidm_state.dat");
                string tmpPath = dbPath + ".tmp";

                using (StreamWriter sw = new StreamWriter(tmpPath, false, Encoding.UTF8))
                {
                    sw.WriteLine(string.Format(CultureInfo.InvariantCulture, "CFG\t{0}\t{1}\t{2}\t{3}\t{4}\t{5}",
                        _defaultThreads, _maxConcurrent, (int)_limiter.GetLimitKbps(),
                        _verifySha256 ? 1 : 0, _clipboardMonitor ? 1 : 0, _darkTheme ? 1 : 0));

                    for (int i = 0; i < _tasks.Count; i++)
                    {
                        DownloadTask t = _tasks[i];
                        DownloadState st = t.Status;
                        if (st == DownloadState.Downloading || st == DownloadState.Connecting || st == DownloadState.Finalizing)
                        {
                            st = DownloadState.Paused;
                        }

                        sw.WriteLine(string.Format(CultureInfo.InvariantCulture,
                            "TASK\t{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}\t{8}\t{9}\t{10}\t{11}",
                            t.Id, t.Url, t.FileName, t.Category, t.SaveDir, t.NumThreads,
                            t.TotalSize, t.SupportsRanges ? 1 : 0, t.IsHls ? 1 : 0,
                            t.DirectWrite ? 1 : 0, (int)st, t.Sha256Hash));

                        lock (t.SyncLock)
                        {
                            for (int s = 0; s < t.Segments.Count; s++)
                            {
                                DownloadSegment seg = t.Segments[s];
                                sw.WriteLine(string.Format(CultureInfo.InvariantCulture,
                                    "SEG\t{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}",
                                    t.Id, seg.Index, seg.Start, seg.End, seg.Current,
                                    seg.Downloaded, seg.Done ? 1 : 0, seg.SegmentUrl ?? ""));
                            }
                        }
                    }
                }

                if (File.Exists(dbPath)) File.Delete(dbPath);
                File.Move(tmpPath, dbPath);
            }
            catch { }
        }

        private void LoadState()
        {
            try
            {
                string dbPath = Path.Combine(AppPaths.BaseDownloadDir, "winidm_state.dat");
                if (!File.Exists(dbPath)) return;

                Dictionary<string, DownloadTask> byId = new Dictionary<string, DownloadTask>();
                string[] lines = File.ReadAllLines(dbPath, Encoding.UTF8);

                for (int i = 0; i < lines.Length; i++)
                {
                    string[] cols = lines[i].Split('\t');
                    if (cols.Length == 0) continue;

                    if (cols[0] == "CFG" && cols.Length >= 6)
                    {
                        _defaultThreads = Math.Max(1, Math.Min(32, int.Parse(cols[1])));
                        _maxConcurrent = Math.Max(1, Math.Min(10, int.Parse(cols[2])));
                        _limiter.SetLimitKbps(double.Parse(cols[3], CultureInfo.InvariantCulture));
                        _verifySha256 = (cols[4] != "0");
                        _clipboardMonitor = (cols[5] != "0");
                        if (cols.Length >= 7) _darkTheme = (cols[6] != "0");
                    }
                    else if (cols[0] == "TASK" && cols.Length >= 13)
                    {
                        DownloadTask t = new DownloadTask();
                        t.Id = cols[1];
                        t.Url = cols[2];
                        t.FileName = cols[3];
                        t.Category = cols[4];
                        t.SaveDir = cols[5];
                        t.NumThreads = Math.Max(1, Math.Min(32, int.Parse(cols[6])));
                        t.TotalSize = long.Parse(cols[7]);
                        t.SupportsRanges = (cols[8] != "0");
                        t.IsHls = (cols[9] != "0");
                        t.DirectWrite = (cols[10] != "0");
                        t.Status = (DownloadState)int.Parse(cols[11]);
                        t.Sha256Hash = cols[12];
                        t.ComputeSha256 = _verifySha256;
                        t.IsStreamPage = DownloadTask.IsVideoPageUrl(t.Url);

                        if (t.Status == DownloadState.Completed) _notifiedIds.Add(t.Id);
                        _tasks.Add(t);
                        byId[t.Id] = t;
                    }
                    else if (cols[0] == "SEG" && cols.Length >= 9)
                    {
                        DownloadTask parent;
                        if (byId.TryGetValue(cols[1], out parent))
                        {
                            DownloadSegment seg = new DownloadSegment();
                            seg.Index = int.Parse(cols[2]);
                            seg.Start = long.Parse(cols[3]);
                            seg.End = long.Parse(cols[4]);
                            seg.Current = long.Parse(cols[5]);
                            seg.Downloaded = long.Parse(cols[6]);
                            seg.Done = (cols[7] != "0");
                            seg.SegmentUrl = cols[8];
                            parent.Segments.Add(seg);
                        }
                    }
                }
            }
            catch { }
        }
    }

    // ========================================================================
    // APPLICATION ENTRY POINT
    // ========================================================================
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)12288 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            }
            catch
            {
                try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }
            }
            ServicePointManager.DefaultConnectionLimit = 256;
            ServicePointManager.EnableDnsRoundRobin = true;
            ServicePointManager.Expect100Continue = false;
            ServicePointManager.UseNagleAlgorithm = false;

            bool createdNew;
            using (Mutex mutex = new Mutex(true, "WinIDM_SingleInstance_App_Mutex", out createdNew))
            {
                if (!createdNew) return;

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                bool firstRun = false;
                bool minimized = false;
                for (int i = 0; i < args.Length; i++)
                {
                    if (args[i] == "--first-run") firstRun = true;
                    if (args[i] == "--minimized") minimized = true;
                }

                MainForm form = new MainForm(firstRun);
                if (minimized)
                {
                    form.WindowState = FormWindowState.Minimized;
                    form.ShowInTaskbar = false;
                }
                Application.Run(form);
            }
        }
    }
}