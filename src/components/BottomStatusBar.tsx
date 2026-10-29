import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { DeviceSession } from '../types';
import {
  Terminal,
  Activity,
  Wifi,
  Usb,
  Radio
} from 'lucide-react';

interface BottomStatusBarProps {
  selectedSession: DeviceSession | null;
  batteryLevel: number | null;
  onOpenAdbShell?: () => void;
  onOpenDiagnostics?: () => void;
  onOpenSettings?: () => void;
}

export const BottomStatusBar: React.FC<BottomStatusBarProps> = ({
  selectedSession,
  batteryLevel,
  onOpenAdbShell,
  onOpenDiagnostics,
  onOpenSettings,
}) => {
  const [adbVersion, setAdbVersion] = useState<string>('就绪');
  const [isAdbOk, setIsAdbOk] = useState<boolean>(true);

  useEffect(() => {
    let mounted = true;
    invoke<string>('get_adb_version', { customPath: null })
      .then((ver) => {
        if (!mounted) return;
        const firstLine = ver.split('\n')[0] || '';
        const match = firstLine.match(/version\s+([\d.]+)/i);
        setAdbVersion(match ? `v${match[1]}` : '已就绪');
        setIsAdbOk(true);
      })
      .catch(() => {
        if (!mounted) return;
        setAdbVersion('异常');
        setIsAdbOk(false);
      });
    return () => {
      mounted = false;
    };
  }, []);

  const isConnected = selectedSession?.is_connected ?? false;
  const isWireless =
    selectedSession?.active_transport === 'TCP/IP' ||
    selectedSession?.active_transport === 'mDNS';

  return (
    <footer className="h-7 min-h-[28px] max-h-[28px] px-3 bg-[var(--cds-surface-0)] border-t border-[var(--border-subtle)] flex items-center justify-between text-xs text-[var(--text-secondary)] select-none shrink-0 z-30 font-mono tabular-nums">
      {/* Left: Engine & Daemon Status Indicators */}
      <div className="flex items-center gap-3">
        {/* 1. ADB Daemon */}
        <div
          className="flex items-center gap-1.5 cursor-pointer hover:text-[var(--text-primary)] transition-colors group"
          onClick={onOpenDiagnostics}
          title="ADB 守护进程状态 (点击查看诊断)"
        >
          <span className="relative flex items-center justify-center w-2 h-2 shrink-0">
            <span
              className={`w-1.5 h-1.5 rounded-full ${
                isAdbOk
                  ? 'bg-emerald-500 shadow-[0_0_4px_rgba(52,211,153,0.4)]'
                  : 'bg-rose-500 shadow-[0_0_4px_rgba(244,63,94,0.4)]'
              }`}
            />
            {isAdbOk && (
              <span className="absolute inset-0 rounded-full bg-emerald-400/35 animate-ping" />
            )}
          </span>
          <span className="text-[var(--text-primary)] font-bold tracking-tight">ADB</span>
          <span className="text-[var(--text-secondary)] font-semibold">{adbVersion}</span>
          <span className="text-slate-400 dark:text-neutral-500">:5037</span>
        </div>

        <span className="w-[1px] h-3 bg-[var(--border-subtle)]" />

        {/* 2. Scrcpy Stream Engine */}
        <div
          className="flex items-center gap-1.5 cursor-pointer hover:text-[var(--text-primary)] transition-colors group"
          onClick={onOpenSettings}
          title="Scrcpy 视频解码引擎配置"
        >
          <span className="relative flex items-center justify-center w-2 h-2 shrink-0">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 shadow-[0_0_4px_rgba(52,211,153,0.4)]" />
            <span className="absolute inset-0 rounded-full bg-emerald-400/35 animate-ping" />
          </span>
          <span className="text-[var(--text-primary)] font-bold tracking-tight">Scrcpy</span>
          <span className="text-[var(--text-secondary)] font-semibold">v3.1</span>
          <span className="px-1.5 py-[1px] text-[10.5px] font-bold rounded-md bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 leading-tight">
            WebCodecs 硬解
          </span>
        </div>

        <span className="w-[1px] h-3 bg-[var(--border-subtle)]" />

        {/* 3. Active Link & Device Status */}
        {selectedSession ? (
          <div className="flex items-center gap-1.5">
            {isWireless ? (
              <Wifi size={13} className="text-blue-500 dark:text-blue-400 shrink-0" />
            ) : (
              <Usb size={13} className="text-blue-500 dark:text-blue-400 shrink-0" />
            )}
            <span className="text-[var(--text-primary)] font-semibold truncate max-w-[140px]">
              {selectedSession.name}
            </span>
            <span
              className={`px-1.5 py-[1px] text-[10.5px] font-bold rounded-md leading-tight ${
                isConnected
                  ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-400 border border-emerald-500/25'
                  : 'bg-slate-100 dark:bg-white/[0.06] text-slate-600 dark:text-neutral-400 border border-[var(--border-subtle)]'
              }`}
            >
              {isConnected ? '在线' : '待机'}
            </span>
            {batteryLevel !== null && (
              <span className="text-[var(--text-secondary)] font-semibold">
                {batteryLevel}%
              </span>
            )}
          </div>
        ) : (
          <div className="flex items-center gap-1 text-[var(--text-secondary)]">
            <Radio size={12} className="shrink-0 opacity-70" />
            <span>无活动设备会话</span>
          </div>
        )}
      </div>

      {/* Right: Quick Tools & Diagnostics Entry */}
      <div className="flex items-center gap-2">
        {/* ADB Shell quick launch */}
        {selectedSession && isConnected && onOpenAdbShell && (
          <button
            type="button"
            onClick={onOpenAdbShell}
            className="flex items-center gap-1.5 px-2 py-0.5 rounded-md hover:bg-black/5 dark:hover:bg-white/[0.08] active:bg-black/10 text-slate-700 dark:text-neutral-300 hover:text-slate-900 dark:hover:text-white transition-colors cursor-pointer border border-transparent hover:border-[var(--border-subtle)] text-xs font-semibold"
            title="快捷打开 ADB Shell 终端控制台 (快捷键 Cmd+T)"
          >
            <Terminal size={13} className="text-blue-500 shrink-0" />
            <span className="font-sans">终端控制台</span>
          </button>
        )}

        {/* Diagnostics */}
        {onOpenDiagnostics && (
          <button
            type="button"
            onClick={onOpenDiagnostics}
            className="flex items-center gap-1.5 px-2 py-0.5 rounded-md hover:bg-black/5 dark:hover:bg-white/[0.08] active:bg-black/10 text-slate-700 dark:text-neutral-300 hover:text-slate-900 dark:hover:text-white transition-colors cursor-pointer border border-transparent hover:border-[var(--border-subtle)] text-xs font-semibold"
            title="查看系统调试与连接诊断"
          >
            <Activity size={13} className="text-emerald-500 shrink-0" />
            <span className="font-sans">诊断</span>
          </button>
        )}

        <span className="w-[1px] h-3 bg-[var(--border-subtle)]" />

        {/* App Version Tag */}
        <span className="text-slate-400 dark:text-neutral-500 text-[11px] font-sans">Screen Remote</span>
      </div>
    </footer>
            title="快捷打开 ADB Shell 终端控制台 (快捷键 Cmd+T)"
          >
            <Terminal size={11.5} className="text-[var(--cds-clay)] shrink-0" />
            <span className="text-[11px]">终端控制台</span>
          </button>
        )}

        {/* Diagnostics */}
        {onOpenDiagnostics && (
          <button
            type="button"
            onClick={onOpenDiagnostics}
            className="flex items-center gap-1 px-1.5 py-0.5 rounded hover:bg-white/[0.06] active:bg-white/[0.1] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors cursor-pointer border border-transparent hover:border-[var(--border-subtle)]"
            title="查看系统调试与连接诊断"
          >
            <Activity size={11.5} className="text-emerald-400 shrink-0" />
            <span className="text-[11px]">诊断</span>
          </button>
        )}

        <span className="w-[1px] h-3 bg-[var(--border-subtle)]" />

        {/* App Version Tag */}
        <span className="text-[var(--text-tertiary)] text-[10.5px]">Screen Remote</span>
      </div>
    </footer>
  );
};
