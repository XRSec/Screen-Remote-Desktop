import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { DeviceSession, AppSettings } from '../../types';
import { ScreenCanvas } from '../ScreenCanvas';
import {
  ExternalLink,
  ArrowDownToLine,
  Smartphone,
  Layers,
  X,
  Maximize2,
  LayoutGrid,
  Radio,
  RefreshCw,
} from 'lucide-react';

interface ActiveScreenTab {
  id: string;
  title: string;
  isVirtualDisplay: boolean;
  startApp?: string;
}

interface ScreensViewProps {
  session: DeviceSession;
  connectedSessions?: DeviceSession[];
  onSelectSession?: (session: DeviceSession) => void;
  battery: number | null;
  settings: AppSettings;
  onOpenSettings: () => void;
  onStartSession?: (sessionId: string) => void;
  // External triggers for launching virtual display apps
  activeVirtualTabs?: ActiveScreenTab[];
  onCloseVirtualTab?: (id: string) => void;
  detachedScreens?: Set<string>;
  onPopOutScreen?: (screenId: string, title?: string) => void;
  onDockScreen?: (screenId: string) => void;
}

export const ScreensView: React.FC<ScreensViewProps> = ({
  session,
  connectedSessions = [],
  onSelectSession,
  activeVirtualTabs = [],
  onCloseVirtualTab,
  detachedScreens: externalDetachedScreens,
  onPopOutScreen,
  onDockScreen,
  onStartSession,
}) => {
  const [localDetachedScreens, setLocalDetachedScreens] = useState<Set<string>>(new Set());
  const [activeTabId, setActiveTabId] = useState<string>('primary');
  const [viewMode, setViewMode] = useState<'tab' | 'grid'>('tab');

  const detachedScreens = externalDetachedScreens ?? localDetachedScreens;
  const serial = session.active_serial || session.connections[0]?.serial || session.connections[0]?.host || '';

  // Combine primary screen tab and any active virtual display tabs
  const tabs: ActiveScreenTab[] = useMemo(
    () => [
      {
        id: 'primary',
        title: session.name ? `${session.name} · 主屏幕` : '主屏幕',
        isVirtualDisplay: false,
      },
      ...activeVirtualTabs,
    ],
    [session.name, activeVirtualTabs]
  );

  // Auto-correct active tab if previous active tab was closed
  useEffect(() => {
    if (!tabs.some((t) => t.id === activeTabId)) {
      setActiveTabId('primary');
    }
  }, [tabs, activeTabId]);

  // Pop out screen into an independent lightweight child window
  const handlePopOut = useCallback(
    async (tab: ActiveScreenTab) => {
      if (onPopOutScreen) {
        onPopOutScreen(tab.id, `${session.name || 'Android'} - ${tab.title}`);
        return;
      }

      const isVirtual = tab.isVirtualDisplay;
      const width = isVirtual ? 1200 : 1080;
      const height = isVirtual ? 800 : 2400;

      try {
        await invoke('open_detached_screen_window', {
          sessionId: session.id,
          screenId: tab.id,
          title: `${session.name || 'Android'} - ${tab.title}`,
          width,
          height,
        });

        setLocalDetachedScreens((prev) => {
          const next = new Set(prev);
          next.add(tab.id);
          return next;
        });
      } catch (err) {
        console.error('Failed to open detached screen window:', err);
      }
    },
    [session.id, session.name, onPopOutScreen]
  );

  // Dock detached screen back to the main window
  const handleDock = useCallback(
    async (screenId: string) => {
      if (onDockScreen) {
        onDockScreen(screenId);
        return;
      }

      try {
        await invoke('close_detached_screen_window', {
          sessionId: session.id,
          screenId,
        });
      } catch (err) {
        console.error('Failed to close detached screen window:', err);
      }

      setLocalDetachedScreens((prev) => {
        const next = new Set(prev);
        next.delete(screenId);
        return next;
      });
    },
    [session.id, onDockScreen]
  );

  // Listen for detached window close events to automatically restore inline display
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let mounted = true;

    listen<{ session_id: string; screen_id: string }>('detached_screen_closed', (event) => {
      const { session_id, screen_id } = event.payload;
      if (session_id === session.id || session_id.startsWith(session.id)) {
        setLocalDetachedScreens((prev) => {
          if (!prev.has(screen_id)) return prev;
          const next = new Set(prev);
          next.delete(screen_id);
          return next;
        });
      }
    })
      .then((fn) => {
        if (!mounted) {
          fn();
        } else {
          unlisten = fn;
        }
      })
      .catch((err) => {
        console.error('Failed to register detached_screen_closed listener:', err);
      });

    return () => {
      mounted = false;
      if (unlisten) unlisten();
    };
  }, [session.id]);

  // Detached placeholder UI for tabs running in separate windows
  const renderDetachedPlaceholder = (tab: ActiveScreenTab) => (
    <div className="w-full h-full flex items-center justify-center p-6 select-none">
      <div className="max-w-md w-full p-8 rounded-3xl backdrop-blur-2xl bg-[var(--bg-card)]/90 border border-[var(--border-subtle)] shadow-[var(--cds-panel-shadow-hover)] flex flex-col items-center text-center relative overflow-hidden">
        {/* Glow behind detached icon */}
        <div className="absolute -top-12 -right-12 w-40 h-40 bg-blue-500/10 rounded-full blur-2xl pointer-events-none" />

        <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-blue-500/20 to-indigo-500/10 border border-blue-500/30 flex items-center justify-center text-blue-400 mb-4 shadow-lg shadow-blue-500/10">
          <ExternalLink size={28} />
        </div>
        <h2 className="text-base font-bold text-[var(--text-primary)] tracking-tight mb-2">
          【{tab.title}】正在独立大窗中运行
        </h2>
        <p className="text-xs text-[var(--text-secondary)] leading-relaxed max-w-sm mb-6">
          当前屏幕画面已分离至独立窗口。您可以自由拖拽至副屏展开协同，或随时收回主工作区。
        </p>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => handlePopOut(tab)}
            className="px-4 py-2.5 rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white text-xs font-semibold flex items-center gap-1.5 shadow-md shadow-blue-600/25 active:scale-95 transition-all cursor-pointer"
          >
            <ExternalLink size={13} />
            <span>切换至独立窗口</span>
          </button>
          <button
            type="button"
            onClick={() => handleDock(tab.id)}
            className="btn btn-secondary px-4 py-2.5 rounded-xl text-xs font-medium flex items-center gap-1.5 cursor-pointer"
          >
            <ArrowDownToLine size={13} />
            <span>收回主工作区</span>
          </button>
        </div>
      </div>
    </div>
  );

  return (
    <div className="flex flex-col w-full h-full bg-[var(--bg-canvas)] overflow-hidden relative select-none">
      {/* ====================================================================
          1. Multi-Screen / Virtual Tab Bar (Rendered when multiple screens exist)
          ==================================================================== */}
      {session.is_connected && tabs.length > 1 && (
        <div className="shrink-0 h-12 px-5 flex items-center justify-between border-b border-[var(--border-subtle)] bg-[var(--bg-sidebar)]/80 backdrop-blur-md z-30 select-none">
          {/* Tab List */}
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar py-1">
            {tabs.map((tab) => {
              const isActive = activeTabId === tab.id;
              const isDetached = detachedScreens.has(tab.id);
              return (
                <div
                  key={tab.id}
                  onClick={() => setActiveTabId(tab.id)}
                  className={`group relative flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs transition-all cursor-pointer border ${
                    isActive
                      ? 'bg-[var(--bg-elevated)] text-[var(--text-primary)] font-semibold border-[var(--border-strong)] shadow-sm'
                      : 'bg-transparent text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-hover)] border-transparent'
                  }`}
                >
                  {tab.isVirtualDisplay ? (
                    <Layers size={13} className={isActive ? 'text-blue-400' : 'text-[var(--text-tertiary)]'} />
                  ) : (
                    <Smartphone size={13} className={isActive ? 'text-emerald-400' : 'text-[var(--text-tertiary)]'} />
                  )}
                  <span className="truncate max-w-[140px]">{tab.title}</span>

                  {isDetached && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-md bg-blue-500/15 text-blue-400 font-medium border border-blue-500/20">
                      独立大窗
                    </span>
                  )}

                  {/* Pop out action */}
                  {!isDetached && (
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        handlePopOut(tab);
                      }}
                      className="opacity-0 group-hover:opacity-100 hover:bg-white/10 p-1 rounded-md text-[var(--text-tertiary)] hover:text-[var(--text-primary)] transition-all cursor-pointer"
                      title="分离至独立大窗"
                    >
                      <ExternalLink size={11} />
                    </button>
                  )}

                  {/* Virtual tab close button */}
                  {tab.id !== 'primary' && onCloseVirtualTab && (
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onCloseVirtualTab(tab.id);
                        if (activeTabId === tab.id) {
                          setActiveTabId('primary');
                        }
                      }}
                      className="opacity-0 group-hover:opacity-100 hover:bg-rose-500/20 hover:text-rose-400 p-1 rounded-md text-[var(--text-tertiary)] transition-all cursor-pointer"
                      title="关闭虚拟显示屏"
                    >
                      <X size={11} />
                    </button>
                  )}
                </div>
              );
            })}
          </div>

          {/* View Mode Segmented Control (Single Focus vs Grid Tile) */}
          <div className="flex items-center gap-1 bg-[var(--bg-canvas)] p-1 rounded-xl border border-[var(--border-subtle)]">
            <button
              type="button"
              onClick={() => setViewMode('tab')}
              className={`px-2.5 py-1 rounded-lg text-xs flex items-center gap-1.5 transition-all cursor-pointer ${
                viewMode === 'tab'
                  ? 'bg-blue-600 text-white shadow-sm font-semibold'
                  : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
              }`}
              title="单屏专注模式"
            >
              <Maximize2 size={12} />
              <span>单屏</span>
            </button>
            <button
              type="button"
              onClick={() => setViewMode('grid')}
              className={`px-2.5 py-1 rounded-lg text-xs flex items-center gap-1.5 transition-all cursor-pointer ${
                viewMode === 'grid'
                  ? 'bg-blue-600 text-white shadow-sm font-semibold'
                  : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
              }`}
              title="平铺多屏模式"
            >
              <LayoutGrid size={12} />
              <span>平铺</span>
            </button>
          </div>
        </div>
      )}

      {/* ====================================================================
          2. Screen Viewport Stage (Active Stream or Open Claude UI Empty State)
          ==================================================================== */}
      <div className="flex-1 w-full h-full overflow-hidden relative bg-[#06070a]">
        {session.is_connected ? (
          tabs.length > 1 && viewMode === 'grid' ? (
            // Grid Tile Mode (Multiple Displays Side by Side)
            <div className="w-full h-full flex flex-row flex-wrap items-center justify-center gap-6 p-6 overflow-auto">
              {tabs.map((tab) => {
                const isDetached = detachedScreens.has(tab.id);
                if (isDetached) {
                  return (
                    <div key={tab.id} className="shrink-0 max-h-full">
                      {renderDetachedPlaceholder(tab)}
                    </div>
                  );
                }
                return (
                  <div key={tab.id} className="shrink-0 h-full max-h-full flex items-center justify-center">
                    <ScreenCanvas
                      sessionId={session.id}
                      serial={serial}
                      sessionTitle={tab.title}
                      isVirtualDisplay={tab.isVirtualDisplay}
                      startApp={tab.startApp}
                      onClose={
                        tab.id !== 'primary' && onCloseVirtualTab
                          ? () => onCloseVirtualTab(tab.id)
                          : undefined
                      }
                    />
                  </div>
                );
              })}
            </div>
          ) : (
            // Single Display Focus Mode
            (() => {
              const currentTab = tabs.find((t) => t.id === activeTabId) || tabs[0];
              const isDetached = detachedScreens.has(currentTab.id);
              if (isDetached) {
                return renderDetachedPlaceholder(currentTab);
              }
              return (
                <div className="w-full h-full flex items-center justify-center overflow-hidden">
                  <ScreenCanvas
                    sessionId={session.id}
                    serial={serial}
                    sessionTitle={currentTab.title}
                    isVirtualDisplay={currentTab.isVirtualDisplay}
                    startApp={currentTab.startApp}
                    onClose={
                      currentTab.id !== 'primary' && onCloseVirtualTab
                        ? () => onCloseVirtualTab(currentTab.id)
                        : undefined
                    }
                  />
                </div>
              );
            })()
          )
        ) : (
          /* ====================================================================
             3. High-Standard Open Claude UI Standby / Empty State
             ==================================================================== */
          <div className="w-full h-full flex items-center justify-center p-6 relative overflow-hidden select-none">
            {/* Ambient Radial Tech Halo */}
            <div className="absolute w-[600px] h-[600px] bg-gradient-to-tr from-blue-600/10 via-indigo-600/5 to-transparent rounded-full blur-3xl pointer-events-none" />

            {/* Central Claude CDS Glassmorphic Panel */}
            <div className="relative flex flex-col items-center max-w-md w-full p-8 md:p-9 rounded-3xl backdrop-blur-2xl bg-[var(--bg-card)]/80 border border-[var(--border-subtle)] shadow-[var(--cds-panel-shadow)] text-center transition-all duration-300 hover:shadow-[var(--cds-panel-shadow-hover)]">
              {/* If current device is offline, but another device is online, show high-contrast quick switcher */}
              {!session.is_connected && connectedSessions.length > 0 && (
                <div className="w-full mb-6 p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/25 flex items-center justify-between gap-3 text-left">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-ping shrink-0" />
                    <div className="min-w-0">
                      <div className="text-xs font-bold text-emerald-400 truncate">
                        发现可用在线设备：{connectedSessions[0].name}
                      </div>
                      <div className="text-[11px] text-[var(--text-secondary)] truncate">
                        当前【{session.name}】离线，点击右侧立即切换
                      </div>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => onSelectSession?.(connectedSessions[0])}
                    className="px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs shrink-0 cursor-pointer shadow-lg shadow-emerald-600/30 transition-all active:scale-95"
                  >
                    立即切换
                  </button>
                </div>
              )}

              {/* Dynamic Breathing Base Icon */}
              <div className="relative mb-6">
                <div className="absolute -inset-4 bg-gradient-to-tr from-amber-500/10 to-rose-500/10 rounded-full blur-xl animate-pulse" />
                <div className="relative w-18 h-18 rounded-2xl bg-gradient-to-br from-neutral-800/80 to-neutral-900/90 border border-white/10 flex items-center justify-center text-neutral-400 shadow-2xl">
                  <Smartphone size={36} strokeWidth={1.75} className="opacity-60" />
                </div>
              </div>

              {/* Status Header */}
              <div className="flex items-center gap-2 mb-2">
                <span className="w-2 h-2 rounded-full bg-amber-500/80" />
                <span className="text-xs font-semibold text-amber-400 uppercase tracking-wider">
                  设备离线 · 未检测到 ADB 连接
                </span>
              </div>

              <h2 className="text-xl font-extrabold text-[var(--text-primary)] tracking-tight mb-2">
                {session.name || 'Android 目标设备'}
              </h2>
              <p className="text-xs text-[var(--text-secondary)] leading-relaxed mb-6 max-w-sm">
                当前未建立 ADB 通信链路。请确保已连接 USB 数据线并在手机上开启【USB 调试】，或在同一局域网下完成配对。
              </p>

              {/* Action Cluster */}
              <div className="w-full flex flex-col gap-2.5">
                <button
                  type="button"
                  onClick={() => {
                    if (onStartSession) {
                      onStartSession(session.id);
                    }
                  }}
                  className="w-full py-3 px-6 rounded-xl bg-gradient-to-r from-blue-600 via-indigo-600 to-blue-500 hover:from-blue-500 hover:to-indigo-500 text-white font-semibold text-xs flex items-center justify-center gap-2 shadow-[0_4px_20px_rgba(59,130,246,0.35),inset_0_1px_0_rgba(255,255,255,0.25)] hover:shadow-[0_6px_24px_rgba(59,130,246,0.55)] active:scale-[0.98] transition-all cursor-pointer"
                >
                  <RefreshCw size={14} className="animate-spin-slow" />
                  <span className="tracking-wide">尝试连接 / 唤醒设备</span>
                </button>
              </div>

              {/* Specs Badge Ribbon */}
              <div className="mt-6 pt-5 w-full border-t border-[var(--border-subtle)] grid grid-cols-3 gap-2 text-[11px] text-[var(--text-tertiary)]">
                <div className="flex flex-col items-center gap-1">
                  <span className="font-semibold text-neutral-400">状态</span>
                  <span className="text-amber-400/90 font-mono">未接入</span>
                </div>
                <div className="flex flex-col items-center gap-1">
                  <span className="font-semibold text-neutral-400">传输通道</span>
                  <span className="font-mono">{session.active_transport || '待分配'}</span>
                </div>
                <div className="flex flex-col items-center gap-1">
                  <span className="font-semibold text-neutral-400">投屏服务</span>
                  <span className="text-blue-400/80 font-mono">就绪待命</span>
                </div>
              </div>

              {/* Bottom Device Serial Pill */}
              <div className="mt-4 flex items-center gap-1.5 text-[10px] text-[var(--text-tertiary)] font-mono">
                <Radio size={11} className="text-[var(--text-tertiary)]" />
                <span>设备通道: {serial || '未分配硬件序列号'}</span>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default ScreensView;
