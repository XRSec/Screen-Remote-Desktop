import React, { useState } from 'react';
import { DeviceSession, AppSection } from '../../types';
import {
  Monitor,
  Smartphone,
  Cpu,
  Wrench,
  Layers,
  Folder,
  Play,
  Terminal,
  Settings,
  BatteryCharging,
  BatteryMedium,
  BatteryLow,
  Wifi,
  Usb,
  Plus,
  ChevronRight,
  CheckCircle2,
  Copy,
  Check,
  Radio,
  Zap,
  Activity,
  Sliders,
  RefreshCw
} from 'lucide-react';

interface HomeOverviewViewProps {
  selectedSession: DeviceSession | null;
  sessions: DeviceSession[];
  onSelectSession: (session: DeviceSession) => void;
  onNavigateSection: (section: AppSection) => void;
  onStartScreenSession: (sessionId: string) => void;
  onOpenAddDevice: () => void;
  onOpenAdbShell: () => void;
  onEditSession?: (session: DeviceSession) => void;
  batteryLevel: number | null;
}

export const HomeOverviewView: React.FC<HomeOverviewViewProps> = ({
  selectedSession,
  sessions,
  onSelectSession,
  onNavigateSection,
  onStartScreenSession,
  onOpenAddDevice,
  onOpenAdbShell,
  onEditSession,
  batteryLevel,
}) => {
  const [copiedSerial, setCopiedSerial] = useState(false);

  const isConnected = selectedSession?.is_connected ?? false;
  const isWireless =
    selectedSession?.active_transport === 'TCP/IP' ||
    selectedSession?.active_transport === 'mDNS';

  const serial =
    selectedSession?.active_serial ||
    selectedSession?.connections[0]?.serial ||
    selectedSession?.connections[0]?.host ||
    '';

  const effectiveBattery = batteryLevel ?? (selectedSession?.battery && selectedSession.battery > 0 ? selectedSession.battery : null);

  const handleCopySerial = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!serial) return;
    navigator.clipboard?.writeText(serial);
    setCopiedSerial(true);
    setTimeout(() => setCopiedSerial(false), 1800);
  };

  const getBatteryColorClass = (val: number) => {
    if (val >= 60) return 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20';
    if (val >= 20) return 'text-amber-400 bg-amber-500/10 border-amber-500/20';
    return 'text-rose-400 bg-rose-500/10 border-rose-500/20';
  };

  const getBatteryFillColor = (val: number) => {
    if (val >= 60) return 'bg-emerald-400';
    if (val >= 20) return 'bg-amber-400';
    return 'bg-rose-400';
  };

  return (
    <div className="screen-workspace-scroll">
      <div className="screen-workspace-centered flex flex-col gap-6 max-w-[940px] pb-12">
        {/* ====================================================================
            1. TOP: Single Visual Hero Card for Currently Selected Device
            ==================================================================== */}
        {selectedSession ? (
          <div className="relative overflow-hidden rounded-3xl border border-[var(--border-subtle)] bg-[var(--bg-card)] p-6 md:p-7 shadow-[var(--cds-panel-shadow)] transition-all duration-300 hover:shadow-[var(--cds-panel-shadow-hover)] hover:border-[var(--border-strong)]">
            {/* Ambient Radial Gradient Glow */}
            <div
              className="absolute -top-24 -left-20 w-80 h-80 rounded-full blur-3xl pointer-events-none opacity-25"
              style={{
                background: `radial-gradient(circle, ${selectedSession.accent || '#3b82f6'} 0%, transparent 70%)`,
              }}
            />

            <div className="relative z-10 flex flex-col gap-5">
              {/* Top Row: Device Identity & Primary Action Button */}
              <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
                {/* Left Info Column */}
                <div className="flex items-start sm:items-center gap-4.5 min-w-0">
                  {/* Hero Device Icon Base */}
                  <div
                    className="relative w-16 h-16 rounded-2xl flex items-center justify-center text-white shrink-0 shadow-lg shadow-black/25 border border-white/20 overflow-hidden"
                    style={{
                      background: `linear-gradient(135deg, ${selectedSession.accent || '#3b82f6'}, #1d4ed8)`,
                    }}
                  >
                    <Smartphone size={32} strokeWidth={1.8} className="drop-shadow-md" />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/20 via-transparent to-white/25 pointer-events-none" />
                  </div>

                  <div className="flex flex-col min-w-0 gap-1.5">
                    {/* Device Title & Quick Model */}
                    <div className="flex items-center gap-3 flex-wrap">
                      <h1 className="text-2xl font-extrabold text-[var(--text-primary)] tracking-tight truncate">
                        {selectedSession.name}
                      </h1>

                      <span className="text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)] font-medium">
                        {selectedSession.model || 'Android 设备'}
                      </span>
                    </div>

                    {/* Metadata Pills: Status, Transport, Battery, System */}
                    <div className="flex items-center gap-2 flex-wrap text-xs">
                      {/* Connection Status Pill with breathing light */}
                      <div
                        className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-semibold border ${
                          isConnected
                            ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30'
                            : 'bg-neutral-500/15 text-neutral-400 border-neutral-500/20'
                        }`}
                      >
                        {isConnected ? (
                          <span className="relative flex h-2 w-2">
                            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
                            <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.9)]" />
                          </span>
                        ) : (
                          <span className="w-2 h-2 rounded-full bg-neutral-400" />
                        )}
                        <span>{isConnected ? 'ADB 调试就绪' : '离线 · 待唤醒'}</span>
                      </div>

                      {/* Transport Pill */}
                      <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] bg-[var(--bg-elevated)] text-[var(--text-secondary)] font-medium border border-[var(--border-subtle)]">
                        {isWireless ? (
                          <Wifi size={12} className="text-sky-400" />
                        ) : (
                          <Usb size={12} className="text-amber-400" />
                        )}
                        <span>
                          {selectedSession.active_transport === 'mDNS'
                            ? 'mDNS · 无线直连'
                            : selectedSession.active_transport === 'USB'
                            ? 'USB · 极速通道'
                            : 'TCP/IP 直连'}
                        </span>
                      </div>

                      {/* Battery Pill with mini-capsule progress bar */}
                      {effectiveBattery !== null && (
                        <div
                          className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-medium border ${getBatteryColorClass(
                            effectiveBattery
                          )}`}
                          title={`当前电量: ${effectiveBattery}%`}
                        >
                          {isConnected ? (
                            <BatteryCharging size={12} className="animate-pulse" />
                          ) : effectiveBattery > 30 ? (
                            <BatteryMedium size={12} />
                          ) : (
                            <BatteryLow size={12} />
                          )}
                          <span className="font-mono">{effectiveBattery}%</span>
                          {/* Mini progress capsule */}
                          <div className="w-7 h-1.5 rounded-full bg-black/20 dark:bg-white/10 overflow-hidden ml-0.5">
                            <div
                              className={`h-full rounded-full transition-all duration-300 ${getBatteryFillColor(
                                effectiveBattery
                              )}`}
                              style={{ width: `${Math.min(100, Math.max(5, effectiveBattery))}%` }}
                            />
                          </div>
                        </div>
                      )}

                      {/* Android OS Version */}
                      <div className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] bg-[var(--bg-elevated)] text-[var(--text-tertiary)] border border-[var(--border-subtle)] font-mono">
                        <span>Android {selectedSession.system_version || '14'}</span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Right Action Cluster: Single Hero Play Action + Subdued Entrances */}
                <div className="flex flex-wrap sm:flex-nowrap items-center gap-2.5 shrink-0 pt-2 lg:pt-0">
                  {/* Hero Action: 启动实时投屏 (在线) 或 尝试连接设备 (离线) */}
                  <button
                    type="button"
                    onClick={() => {
                      onStartScreenSession(selectedSession.id);
                      if (isConnected) {
                        onNavigateSection('screens');
                      }
                    }}
                    className="relative group overflow-hidden px-5 py-2.5 rounded-xl bg-gradient-to-r from-blue-600 via-indigo-600 to-blue-500 hover:from-blue-500 hover:to-indigo-500 text-white font-semibold text-xs flex items-center gap-2 shadow-[0_4px_20px_rgba(59,130,246,0.35),inset_0_1px_0_rgba(255,255,255,0.25)] hover:shadow-[0_6px_26px_rgba(59,130,246,0.55)] active:scale-[0.98] transition-all duration-200 cursor-pointer"
                  >
                    <div className="w-5 h-5 rounded-lg bg-white/20 flex items-center justify-center text-white">
                      {isConnected ? (
                        <Play size={11} fill="currentColor" className="ml-0.5" />
                      ) : (
                        <RefreshCw size={11} />
                      )}
                    </div>
                    <span className="tracking-wide">
                      {isConnected ? '启动实时投屏' : '尝试连接设备'}
                    </span>
                    {/* Subtle top edge shimmer */}
                    <div className="absolute inset-x-0 top-0 h-[1px] bg-gradient-to-r from-transparent via-white/50 to-transparent pointer-events-none" />
                  </button>

                  {/* Secondary Actions with disciplined hierarchy */}
                  <button
                    type="button"
                    onClick={() => onNavigateSection('deviceInfo')}
                    className="btn btn-secondary px-3.5 py-2 text-xs font-medium cursor-pointer flex items-center gap-1.5"
                    title="查看设备架构与硬件参数"
                  >
                    <Cpu size={14} className="text-[var(--text-secondary)]" />
                    <span>硬件参数</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => onNavigateSection('utilities')}
                    className="btn btn-secondary px-3.5 py-2 text-xs font-medium cursor-pointer flex items-center gap-1.5"
                    title="分辨率/DPI/动画等免 Root 调优"
                  >
                    <Wrench size={14} className="text-[var(--text-secondary)]" />
                    <span>系统工具</span>
                  </button>

                  {onEditSession && (
                    <button
                      type="button"
                      onClick={() => onEditSession(selectedSession)}
                      className="btn btn-secondary px-3.5 py-2 text-xs font-medium cursor-pointer flex items-center gap-1.5"
                      title="配置 Scrcpy 传输与画质参数"
                    >
                      <Settings size={14} className="text-[var(--text-secondary)]" />
                      <span>配置会话</span>
                    </button>
                  )}
                </div>
              </div>

              {/* Specs Glance Ribbon (Pro Dashboard Strip) */}
              <div className="pt-3.5 border-t border-[var(--border-subtle)] flex items-center justify-between flex-wrap gap-3 text-xs text-[var(--text-secondary)]">
                <div className="flex items-center gap-4 flex-wrap">
                  {/* Serial with Click to Copy */}
                  <div
                    onClick={handleCopySerial}
                    className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md hover:bg-[var(--bg-hover)] text-[var(--text-tertiary)] hover:text-[var(--text-primary)] cursor-pointer transition-colors font-mono text-[11px]"
                    title="点击复制序列号"
                  >
                    <Radio size={12} className="text-[var(--text-tertiary)]" />
                    <span>序列号: {serial || '未分配'}</span>
                    {copiedSerial ? (
                      <Check size={11} className="text-emerald-400" />
                    ) : (
                      <Copy size={11} className="opacity-60" />
                    )}
                  </div>

                  {/* Stream Preset */}
                  <div className="inline-flex items-center gap-1 text-[var(--text-tertiary)] text-[11px]">
                    <Zap size={12} className="text-amber-400/80" />
                    <span>
                      流画质:{' '}
                      <strong className="text-[var(--text-secondary)] font-medium">
                        {selectedSession.scrcpy_options?.max_size ? `${selectedSession.scrcpy_options.max_size}P` : '原始分辨率'} ·{' '}
                        {selectedSession.scrcpy_options?.max_fps || 60} FPS
                      </strong>
                    </span>
                  </div>

                  {/* Bitrate */}
                  <div className="inline-flex items-center gap-1 text-[var(--text-tertiary)] text-[11px]">
                    <Activity size={12} className="text-blue-400/80" />
                    <span>
                      比特率:{' '}
                      <strong className="text-[var(--text-secondary)] font-medium">
                        {selectedSession.scrcpy_options?.video_bitrate || '8M 动态流'}
                      </strong>
                    </span>
                  </div>
                </div>

                <div className="text-[11px] text-[var(--text-tertiary)]">
                  设备 ID: <span className="font-mono">{selectedSession.id.slice(0, 8)}...</span>
                </div>
              </div>
            </div>
          </div>
        ) : (
          /* Empty Selected Device State */
          <div className="app-card flex flex-col sm:flex-row items-center justify-between p-7 gap-5 border border-[var(--border-subtle)] shadow-[var(--cds-panel-shadow)]">
            <div className="flex items-center gap-4.5">
              <div className="app-icon-tile bg-gradient-to-br from-blue-500 to-indigo-600">
                <Smartphone size={24} />
              </div>
              <div>
                <h2 className="text-base font-bold text-[var(--text-primary)]">未选择任何设备</h2>
                <p className="text-xs text-[var(--text-secondary)] mt-0.5">
                  请从左侧设备列表中选择一个目标会话，或点击右侧按钮添加新设备。
                </p>
              </div>
            </div>
            <button
              type="button"
              onClick={onOpenAddDevice}
              className="btn btn-primary px-4 py-2.5 text-xs font-semibold cursor-pointer flex items-center gap-1.5 shrink-0 shadow-md shadow-blue-500/20"
            >
              <Plus size={14} />
              <span>添加设备会话</span>
            </button>
          </div>
        )}

        {/* ====================================================================
            2. SECTION 2: 6 Core Capability Matrix Cards (Claude CDS Style)
            ==================================================================== */}
        <div className="flex flex-col gap-3.5">
          <div className="flex items-center justify-between px-1">
            <span className="text-xs font-bold text-[var(--text-secondary)] uppercase tracking-wider">
              核心功能与控制中心
            </span>
            <span className="text-[11px] text-[var(--text-tertiary)]">
              点击卡片即可直达对应控制面板
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3.5">
            {/* Card 1: 远程屏幕投屏 */}
            <div
              onClick={() => onNavigateSection('screens')}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#0a84ff] to-[#0071e3]">
                  <Monitor size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20">
                    低延迟
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  远程屏幕投屏
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  原生 Scrcpy 超低延迟传输，支持键鼠映射、虚拟屏扩展与独立大窗
                </p>
              </div>
            </div>

            {/* Card 2: 硬件与系统详情 */}
            <div
              onClick={() => onNavigateSection('deviceInfo')}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#8b5cf6] to-[#6d28d9]">
                  <Cpu size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-purple-500/10 text-purple-400 border border-purple-500/20">
                    硬件级
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  硬件与系统详情
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  SoC 芯片平台、屏幕物理分辨率、DPI、电池健康与各网卡 IP 地址
                </p>
              </div>
            </div>

            {/* Card 3: 系统优化与工具 */}
            <div
              onClick={() => onNavigateSection('utilities')}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#f59e0b] to-[#d97706]">
                  <Sliders size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
                    免 Root
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  系统优化与工具
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  动态 DPI 与分辨率热切换、全局动画缩放调节与屏幕常亮防熄屏
                </p>
              </div>
            </div>

            {/* Card 4: 应用程序管理器 */}
            <div
              onClick={() => onNavigateSection('apps')}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#10b981] to-[#059669]">
                  <Layers size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                    APK 管理
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  应用程序管理器
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  查看已装应用与系统包，拖拽安装 APK、一键提取安装包或停用冻结
                </p>
              </div>
            </div>

            {/* Card 5: 文件系统浏览器 */}
            <div
              onClick={() => onNavigateSection('files')}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#06b6d4] to-[#0284c7]">
                  <Folder size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-sky-500/10 text-sky-400 border border-sky-500/20">
                    双向传输
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  文件系统浏览器
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  macOS Finder 级目录分栏导航，支持大文件高速双向上传与下载
                </p>
              </div>
            </div>

            {/* Card 6: ADB 交互控制台 */}
            <div
              onClick={onOpenAdbShell}
              className="app-card app-card-interactive flex flex-col justify-between p-5 group"
            >
              <div className="flex items-start justify-between">
                <div className="app-icon-tile bg-gradient-to-br from-[#d946ef] to-[#a21caf]">
                  <Terminal size={22} />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-fuchsia-500/10 text-fuchsia-400 border border-fuchsia-500/20">
                    实时 Shell
                  </span>
                  <ChevronRight size={14} className="text-[var(--text-tertiary)] group-hover:text-[var(--text-primary)] group-hover:translate-x-0.5 transition-all" />
                </div>
              </div>
              <div className="mt-4">
                <h3 className="text-sm font-bold text-[var(--text-primary)] tracking-tight">
                  ADB 交互控制台
                </h3>
                <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">
                  零配置即时打开命令调试终端，实时捕获 Logcat 日志与执行脚本
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* ====================================================================
            3. SECTION 3: All Device Sessions List (Polished Matrix Cards)
            ==================================================================== */}
        <div className="flex flex-col gap-3.5">
          <div className="flex items-center justify-between px-1">
            <span className="text-xs font-bold text-[var(--text-secondary)] uppercase tracking-wider">
              全部设备会话 ({sessions.length})
            </span>
            <button
              type="button"
              onClick={onOpenAddDevice}
              className="text-xs text-blue-500 hover:text-blue-400 flex items-center gap-1 cursor-pointer font-medium transition-colors"
            >
              <Plus size={13} />
              <span>添加新设备</span>
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3.5">
            {sessions.map((s) => {
              const isCurr = selectedSession?.id === s.id;
              const isConn = s.is_connected;
              const sSerial =
                s.active_serial || s.connections[0]?.serial || s.connections[0]?.host || '';

              return (
                <div
                  key={s.id}
                  onClick={() => onSelectSession(s)}
                  className={`app-card app-card-interactive p-4.5 flex items-center justify-between gap-3 transition-all ${
                    isCurr
                      ? 'ring-1 ring-blue-500/60 bg-blue-500/[0.06] border-blue-500/30 shadow-[0_0_18px_rgba(59,130,246,0.15)]'
                      : ''
                  }`}
                >
                  <div className="flex items-center gap-3.5 min-w-0">
                    <div
                      className="w-11 h-11 rounded-xl flex items-center justify-center text-white shrink-0 shadow-sm border border-white/10"
                      style={{ backgroundColor: s.accent || '#3b82f6' }}
                    >
                      <Smartphone size={20} strokeWidth={1.8} />
                    </div>

                    <div className="flex flex-col min-w-0 gap-0.5">
                      <span className="text-xs font-bold text-[var(--text-primary)] truncate">
                        {s.name}
                      </span>
                      <div className="flex items-center gap-1.5 text-[11px] truncate">
                        {isConn ? (
                          <span className="inline-flex items-center gap-1 text-emerald-400 font-medium">
                            <span className="relative flex h-1.5 w-1.5">
                              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
                              <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500" />
                            </span>
                            <span>在线</span>
                          </span>
                        ) : (
                          <span className="text-[var(--text-tertiary)] flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-neutral-500" />
                            <span>离线</span>
                          </span>
                        )}
                        <span className="text-[var(--text-tertiary)]">·</span>
                        <span className="text-[var(--text-tertiary)] font-mono truncate max-w-[80px]">
                          {sSerial ? sSerial.slice(-6) : '未知'}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Fast Action Cluster */}
                  <div className="flex items-center gap-1.5 shrink-0">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSelectSession(s);
                        onStartScreenSession(s.id);
                        onNavigateSection('screens');
                      }}
                      className="w-8 h-8 rounded-full bg-blue-500/10 hover:bg-blue-500 text-blue-400 hover:text-white flex items-center justify-center cursor-pointer border border-blue-500/20 hover:border-blue-500 shadow-sm active:scale-95 transition-all"
                      title="快速启动投屏"
                    >
                      <Play size={12} fill="currentColor" className="ml-0.5" />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* ====================================================================
            4. SECTION 4: Engine Readiness Status Ribbon
            ==================================================================== */}
        <div className="p-4 rounded-2xl bg-[var(--bg-card)] border border-[var(--border-subtle)] flex items-center justify-between flex-wrap gap-3.5 text-xs text-[var(--text-secondary)] shadow-[var(--cds-panel-shadow)]">
          <div className="flex items-center gap-2">
            <CheckCircle2 size={14} className="text-emerald-500" />
            <span>
              ADB 调试桥: <strong className="text-[var(--text-primary)] font-medium">服务就绪</strong>
            </span>
          </div>
          <div className="flex items-center gap-2">
            <CheckCircle2 size={14} className="text-emerald-500" />
            <span>
              Scrcpy 协议服务: <strong className="text-[var(--text-primary)] font-medium">v4.1 就绪</strong>
            </span>
          </div>
          <div className="flex items-center gap-2">
            <CheckCircle2 size={14} className="text-emerald-500" />
            <span>
              WebCodecs 硬件加速: <strong className="text-[var(--text-primary)] font-medium">低延迟解码</strong>
            </span>
          </div>
          <div className="flex items-center gap-2">
            <CheckCircle2 size={14} className="text-emerald-500" />
            <span>
              虚拟扩展屏 (AVD): <strong className="text-[var(--text-primary)] font-medium">多显示器支持</strong>
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};
