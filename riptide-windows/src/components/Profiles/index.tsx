import { useState } from 'react';
import { useRiptideStore } from '../../stores/riptide';
import { Plus, Trash2, Edit3, Download, FileText } from 'lucide-react';
import * as tauri from '../../services/tauri';

export function Profiles() {
  const { profiles, addProfile, removeProfile, setActiveProfile } = useRiptideStore();
  const [newProfileName, setNewProfileName] = useState('');
  const [newProfileContent, setNewProfileContent] = useState('');
  const [importUrl, setImportUrl] = useState('');
  const [showAddModal, setShowAddModal] = useState(false);
  const [showImportModal, setShowImportModal] = useState(false);

  const handleAddProfile = async () => {
    if (!newProfileName.trim()) return;

    try {
      const profile = await tauri.addProfile(
        newProfileName,
        newProfileContent || '# Profile configuration\n',
      );

      addProfile(profile);
      setNewProfileName('');
      setNewProfileContent('');
      setShowAddModal(false);
    } catch (error) {
      console.error('Failed to add profile:', error);
    }
  };

  const handleImportFromUrl = async () => {
    if (!importUrl.trim()) return;
    
    try {
      const profile = await tauri.importProfileFromUrl(importUrl);
      addProfile(profile);
      setImportUrl('');
      setShowImportModal(false);
    } catch (error) {
      console.error('Failed to import:', error);
    }
  };

  const handleDelete = async (id: string) => {
    try {
      await tauri.removeProfile(id);
      removeProfile(id);
    } catch (error) {
      console.error('Failed to remove profile:', error);
    }
  };

  const handleActivate = async (id: string) => {
    try {
      await tauri.setActiveProfile(id);
      setActiveProfile(id);
    } catch (error) {
      console.error('Failed to activate profile:', error);
    }
  };

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-slate-100">配置文件</h2>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowImportModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
          >
            <Download size={14} />
            从 URL 导入
          </button>
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
          >
            <Plus size={14} />
            新建配置
          </button>
        </div>
      </div>

      {/* Profile list */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {profiles.map((profile) => (
          <div 
            key={profile.id}
            className="bg-slate-900/50 border border-slate-800 rounded-xl p-4 hover:border-slate-700 transition-colors"
          >
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-2 min-w-0">
                <FileText size={18} className="text-blue-400 flex-shrink-0" />
                <h3 className="font-semibold text-slate-100 text-sm truncate">{profile.name}</h3>
              </div>
              <button
                onClick={() => handleDelete(profile.id)}
                className="text-slate-500 hover:text-red-400 transition-colors p-1 rounded hover:bg-slate-800"
                title="删除配置"
              >
                <Trash2 size={14} />
              </button>
            </div>
            
            <p className="text-xs text-slate-500 mb-3">
              更新于: {new Date(profile.updated_at).toLocaleDateString()}
            </p>
            
            <div className="flex items-center gap-2">
              <button
                onClick={() => handleActivate(profile.id)}
                className="flex-1 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded-lg text-xs font-medium transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                激活
              </button>
              <button className="p-1.5 bg-slate-800 hover:bg-slate-700 text-slate-400 rounded-lg transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50">
                <Edit3 size={14} />
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Add Profile Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 w-full max-w-lg shadow-2xl">
            <h3 className="text-base font-semibold text-slate-100 mb-3">新建配置</h3>
            <input
              type="text"
              placeholder="配置名称"
              value={newProfileName}
              onChange={(e) => setNewProfileName(e.target.value)}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 mb-3 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all"
            />
            <textarea
              placeholder="配置内容 (YAML)"
              value={newProfileContent}
              onChange={(e) => setNewProfileContent(e.target.value)}
              rows={8}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 mb-4 font-mono focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all"
            />
            <div className="flex items-center justify-end gap-2">
              <button
                onClick={() => setShowAddModal(false)}
                className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 rounded"
              >
                取消
              </button>
              <button
                onClick={handleAddProfile}
                className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              >
                创建
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Import Modal */}
      {showImportModal && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 w-full max-w-lg shadow-2xl">
            <h3 className="text-base font-semibold text-slate-100 mb-3">从 URL 导入</h3>
            <input
              type="text"
              placeholder="订阅链接"
              value={importUrl}
              onChange={(e) => setImportUrl(e.target.value)}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 mb-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all"
            />
            <div className="flex items-center justify-end gap-2">
              <button
                onClick={() => setShowImportModal(false)}
                className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 rounded"
              >
                取消
              </button>
              <button
                onClick={handleImportFromUrl}
                className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              >
                导入
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
