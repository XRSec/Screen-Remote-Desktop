import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { SkinInfo } from '../../types';
import {
  Smartphone,
  Tablet,
  Tv,
  X
} from 'lucide-react';

interface CreateVirtualDeviceModalProps {
  onClose: () => void;
  onCreated: () => void;
}

export const CreateVirtualDeviceModal: React.FC<CreateVirtualDeviceModalProps> = ({
  onClose,
  onCreated,
}) => {
  const [deviceType, setDeviceType] = useState<'phone' | 'tablet' | 'tv'>('phone');
  const [skins, setSkins] = useState<SkinInfo[]>([]);
  const [selectedSkin, setSelectedSkin] = useState<string>('galaxy_nexus');

  useEffect(() => {
    invoke<SkinInfo[]>('list_available_skins')
      .then((data) => {
        if (data.length > 0) {
          setSkins(data);
          setSelectedSkin(data[0].name);
        }
      })
      .catch((err) => console.error('Failed to load skins:', err));
  }, []);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div
      onClick={onClose}
      className="modal-backdrop select-none"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="modal-window-card w-full max-w-[800px] h-[660px] max-h-[90vh]"
      >
        {/* Header */}
        <div className="modal-titlebar">
          <div>
            <h2 className="text-sm font-semibold text-[var(--text-primary)] tracking-wide">创建虚拟设备</h2>
            <p className="text-[11px] text-[var(--text-secondary)]">选择设备类型、外观、系统镜像和硬件参数</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="modal-close-icon-btn"
          >
            <X size={15} />
          </button>
        </div>

        {/* Form Body */}
        <div className="modal-body-scroll p-6 flex flex-col gap-6">
          {/* Step 1: 设备类型 */}
          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-2 text-xs font-bold text-[var(--text-primary)]">
              <span className="w-5 h-5 rounded-full bg-[var(--cds-clay)] text-white flex items-center justify-center text-[11px]">
                1
              </span>
              设备类型
            </div>

            <div className="grid grid-cols-3 gap-3">
              <button
                type="button"
                onClick={() => setDeviceType('phone')}
                className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all cursor-pointer ${
                  deviceType === 'phone'
                    ? 'bg-blue-50 dark:bg-blue-600/15 border-blue-500 text-blue-900 dark:text-blue-100 shadow-xs ring-1 ring-blue-400/30 font-bold'
                    : 'bg-white dark:bg-slate-900 border-slate-200 dark:border-white/10 text-slate-700 dark:text-slate-300 hover:border-slate-300'
                }`}
              >
                <Smartphone size={30} className="mb-2 text-blue-600 dark:text-blue-400" />
                <span className="text-sm font-bold">手机</span>
              </button>

              <button
                type="button"
                onClick={() => setDeviceType('tablet')}
                className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all cursor-pointer ${
                  deviceType === 'tablet'
                    ? 'bg-blue-50 dark:bg-blue-600/15 border-blue-500 text-blue-900 dark:text-blue-100 shadow-xs ring-1 ring-blue-400/30 font-bold'
                    : 'bg-white dark:bg-slate-900 border-slate-200 dark:border-white/10 text-slate-700 dark:text-slate-300 hover:border-slate-300'
                }`}
              >
                <Tablet size={30} className="mb-2 text-blue-600 dark:text-blue-400" />
                <span className="text-sm font-bold">平板</span>
              </button>

              <button
                type="button"
                onClick={() => setDeviceType('tv')}
                className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all cursor-pointer ${
                  deviceType === 'tv'
                    ? 'bg-blue-50 dark:bg-blue-600/15 border-blue-500 text-blue-900 dark:text-blue-100 shadow-xs ring-1 ring-blue-400/30 font-bold'
                    : 'bg-white dark:bg-slate-900 border-slate-200 dark:border-white/10 text-slate-700 dark:text-slate-300 hover:border-slate-300'
                }`}
              >
                <Tv size={30} className="mb-2 text-blue-600 dark:text-blue-400" />
                <span className="text-sm font-bold">电视</span>
              </button>
            </div>
          </div>

          {/* Step 2: 设备外观 */}
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-sm font-bold text-slate-900 dark:text-white">
                <span className="w-5 h-5 rounded-full bg-blue-600 text-white flex items-center justify-center text-xs font-bold">
                  2
                </span>
                设备外观
              </div>

              <div className="flex items-center gap-2">
                <span className="text-xs font-mono font-medium text-slate-500 dark:text-slate-400">{skins.length || 9} 个可用外观</span>
              </div>
            </div>

            {/* Skins Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3 max-h-[300px] overflow-y-auto pr-1">
              {(skins.length > 0 ? skins : [
                { name: 'Galaxy Nexus', width: 720, height: 1280, form_factor: 'phone', path: '' },
                { name: 'Nexus 4', width: 768, height: 1280, form_factor: 'phone', path: '' },
                { name: 'Nexus 5', width: 1080, height: 1920, form_factor: 'phone', path: '' },
                { name: 'Pixel 3', width: 1080, height: 2160, form_factor: 'phone', path: '' },
                { name: 'Galaxy Tab A11', width: 800, height: 1340, form_factor: 'tablet', path: '' },
              ]).map((skin, idx) => {
                const isSelected = selectedSkin === skin.name;
                return (
                  <div
                    key={`${skin.name}-${idx}`}
                    onClick={() => setSelectedSkin(skin.name)}
                    className={`flex flex-col items-center justify-between p-3 rounded-xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-blue-50 dark:bg-blue-600/15 border-blue-500 text-blue-950 dark:text-white shadow-xs ring-1 ring-blue-400/30'
                        : 'bg-white dark:bg-slate-900 border-slate-200 dark:border-white/10 hover:border-slate-300 text-slate-800 dark:text-slate-200 shadow-xs'
                    }`}
                  >
                    <div className="h-20 w-12 border border-slate-200 dark:border-white/10 rounded-lg flex items-center justify-center my-2 bg-slate-50 dark:bg-black/30 shadow-inner">
                      <Smartphone size={22} className={isSelected ? 'text-blue-600 dark:text-blue-400' : 'text-slate-400 dark:text-neutral-500'} />
                    </div>
                    <div className="text-center w-full">
                      <div className="text-xs font-bold text-slate-900 dark:text-white truncate">{skin.name}</div>
                      <div className="text-[11px] font-mono text-slate-500 dark:text-slate-400 mt-0.5">
                        {skin.width} × {skin.height}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="modal-footer justify-end">
          <button
            type="button"
            onClick={onClose}
            className="btn btn-secondary px-4 py-1.5 text-xs"
          >
            取消
          </button>
          <button
            type="button"
            onClick={onCreated}
            className="btn btn-primary px-5 py-1.5 text-xs font-semibold"
          >
            创建设备
          </button>
        </div>
      </div>
    </div>
  );
};
