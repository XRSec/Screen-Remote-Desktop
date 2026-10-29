import React from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { AppSection } from '../types';
import {
  Home,
  Monitor,
  Info,
  Wrench,
  Folder,
  Layers,
  Activity,
  ArrowLeftRight,
  Bell,
  MessageSquare,
  Image,
  RotateCw,
  Settings,
  Smartphone
} from 'lucide-react';

interface TopBarProps {
  currentSection: AppSection;
  onSelectSection: (section: AppSection) => void;
  onRefresh: () => void;
  isRefreshing: boolean;
  onOpenSettings: () => void;
  hasSelectedDevice: boolean;
  selectedDeviceName?: string;
  isDeviceConnected?: boolean;
}

interface SectionItem {
  id: AppSection;
  title: string;
  tooltip: string;
  icon: React.ReactNode;
}

const SECTIONS: SectionItem[] = [
  { id: 'screens', title: '屏幕', tooltip: '实时屏幕投屏与操控', icon: <Monitor size={15} /> },
  { id: 'home', title: '概览', tooltip: '设备核心控制驾驶舱', icon: <Home size={15} /> },
  { id: 'deviceInfo', title: '信息', tooltip: '硬件与系统信息', icon: <Info size={15} /> },
  { id: 'utilities', title: '工具', tooltip: '实用工具箱', icon: <Wrench size={15} /> },
  { id: 'apps', title: '应用', tooltip: '应用程序管理', icon: <Layers size={15} /> },
  { id: 'files', title: '文件', tooltip: '文件系统浏览器', icon: <Folder size={15} /> },
  { id: 'processes', title: '进程', tooltip: '进程管理器', icon: <Activity size={15} /> },
  { id: 'portForward', title: '端口', tooltip: '端口转发规则', icon: <ArrowLeftRight size={15} /> },
  { id: 'notifications', title: '通知', tooltip: '设备通知推送', icon: <Bell size={15} /> },
  { id: 'messages', title: '消息', tooltip: '短信与即时消息', icon: <MessageSquare size={15} /> },
  { id: 'photos', title: '相册', tooltip: '媒体相册浏览器', icon: <Image size={15} /> },
];

const REFRESHABLE_SECTIONS = [
  'home',
  'files',
  'apps',
  'processes',
  'deviceInfo',
  'notifications',
  'messages',
  'photos',
  'portForward',
];

export const TopBar: React.FC<TopBarProps> = ({
  currentSection,
  onSelectSection,
  onRefresh,
  isRefreshing,
  onOpenSettings,
  hasSelectedDevice,
  selectedDeviceName,
  isDeviceConnected,
}) => {
  const handleMouseDown = (e: React.MouseEvent) => {
    if (
      e.button === 0 &&
      !(e.target as HTMLElement).closest('button, input, select, [data-no-drag]')
    ) {
      getCurrentWindow().startDragging();
    }
  };

  const isRefreshable = REFRESHABLE_SECTIONS.includes(currentSection) && hasSelectedDevice;

  return (
    <header
      className="h-12 min-h-12 px-3.5 flex items-center justify-between border-b border-[var(--border-subtle)] bg-[var(--cds-surface-1)] w-full select-none shrink-0 gap-3 relative z-30"
      data-tauri-drag-region
      onMouseDown={handleMouseDown}
    >
      {/* 左侧：当前设备状态指示药丸 */}
      <div className="flex items-center shrink-0 min-w-0" data-no-drag>
        {selectedDeviceName ? (
          <div
            className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/80 dark:bg-slate-900/80 hover:bg-white dark:hover:bg-slate-900 border border-slate-200 dark:border-white/10 backdrop-blur-md shadow-xs transition-all duration-150"
            title={`当前设备: ${selectedDeviceName} (${isDeviceConnected ? '已连接' : '待命'})`}
          >
            <Smartphone size={14} className="text-slate-500 dark:text-slate-400 shrink-0" />
            <div className="relative flex items-center justify-center shrink-0">
              <span
                className={`w-2 h-2 rounded-full ${
                  isDeviceConnected
                    ? 'bg-emerald-500 shadow-[0_0_8px_#10b981]'
                    : 'bg-slate-400 dark:bg-neutral-500'
                }`}
              />
              {isDeviceConnected && (
                <span className="animate-ping absolute inline-flex h-2 w-2 rounded-full bg-emerald-400 opacity-60" />
              )}
            </div>
            <span className="text-[13px] font-bold text-slate-900 dark:text-white truncate max-w-[100px] sm:max-w-[160px]">
              {selectedDeviceName}
            </span>
            <span className="text-[11px] font-mono font-semibold text-slate-500 dark:text-slate-400">
              {isDeviceConnected ? '在线' : '离线'}
            </span>
          </div>
        ) : (
          <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/60 dark:bg-slate-900/60 border border-slate-200 dark:border-white/10 text-slate-500 dark:text-slate-400 text-xs font-medium">
            <span className="w-1.5 h-1.5 rounded-full bg-slate-400 dark:bg-neutral-600" />
            <span>未连接设备</span>
          </div>
        )}
      </div>

      {/* 中间：现代分段控制滑动标签栏 (Segmented Track) */}
      <div className="flex-1 flex items-center justify-center min-w-0 overflow-x-auto no-scrollbar py-0.5">
        <div
          className="inline-flex items-center p-1 rounded-xl bg-slate-200/80 dark:bg-black/35 border border-slate-300/80 dark:border-white/10 backdrop-blur-md shadow-inner gap-0.5 shrink-0 max-w-full"
          data-no-drag
        >
          {SECTIONS.map((sec) => {
            const isSelected = currentSection === sec.id;
            return (
              <button
                key={sec.id}
                type="button"
                data-no-drag
                onClick={() => onSelectSection(sec.id)}
                className={`relative flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] transition-all duration-150 select-none whitespace-nowrap cursor-pointer shrink-0 ${
                  isSelected
                    ? 'bg-white dark:bg-slate-800 text-blue-600 dark:text-blue-400 font-bold border border-slate-200 dark:border-white/10 shadow-xs'
                    : 'text-slate-700 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-300/50 dark:hover:bg-white/10 border border-transparent font-medium'
                }`}
                title={sec.tooltip}
              >
                <span
                  className={`shrink-0 transition-colors ${
                    isSelected ? 'text-blue-600 dark:text-blue-400' : 'text-slate-500 dark:text-slate-400'
                  }`}
                >
                  {sec.icon}
                </span>
                <span className="truncate">{sec.title}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* 右侧：操作按钮组 (刷新与偏好设置) */}
      <div className="flex items-center gap-1.5 shrink-0" data-no-drag>
        {isRefreshable && (
          <button
            type="button"
            onClick={onRefresh}
            disabled={isRefreshing}
            className="w-8 h-8 rounded-lg bg-[var(--cds-surface-2)]/60 hover:bg-[var(--cds-surface-2)] active:bg-[var(--cds-surface-hover)] border border-[var(--border-subtle)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] flex items-center justify-center transition-all cursor-pointer shadow-sm active:scale-95 disabled:opacity-40"
            title="刷新当前页面数据"
          >
            <RotateCw
              size={13.5}
              className={`transition-transform duration-300 ${
                isRefreshing ? 'animate-spin text-[var(--cds-clay)]' : ''
              }`}
            />
          </button>
        )}

        <button
          type="button"
          onClick={onOpenSettings}
          className="w-8 h-8 rounded-lg bg-[var(--cds-surface-2)]/60 hover:bg-[var(--cds-surface-2)] active:bg-[var(--cds-surface-hover)] border border-[var(--border-subtle)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] flex items-center justify-center transition-all cursor-pointer shadow-sm active:scale-95"
          title="全局偏好设置"
        >
          <Settings size={14} />
        </button>
      </div>
    </header>
  );
};
