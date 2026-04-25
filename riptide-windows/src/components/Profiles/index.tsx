import { useState } from 'react';
import { useRiptideStore } from '../../stores/riptide';
import { Plus, Trash2, Edit3, Download, FileText } from 'lucide-react';
import type { Profile } from '../../types';
import * as tauri from '../../services/tauri';

export function Profiles() {
  const { profiles, addProfile, removeProfile, setActiveProfile } = useRiptideStore();
  const [newProfileName, setNewProfileName] = useState('');
  const [newProfileContent, setNewProfileContent] = useState('');
  const [importUrl, setImportUrl] = useState('');
  const [showAddModal, setShowAddModal] = useState(false);
  const [showImportModal, setShowImportModal] = useState(false);
  const [showShareUriModal, setShowShareUriModal] = useState(false);
  const [shareUri, setShareUri] = useState('');
  const [editingProfile, setEditingProfile] = useState<Profile | null>(null);
  const [editContent, setEditContent] = useState('');
  const [saving, setSaving] = useState(false);

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

  const handleImportFromShareUri = async () => {
    if (!shareUri.trim()) return;

    try {
      const profile = await tauri.importShareUri(shareUri.trim());
      addProfile(profile);
      setShareUri('');
      setShowShareUriModal(false);
    } catch (error) {
      console.error('Failed to import share URI:', error);
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

  const handleEdit = (profile: Profile) => {
    setEditingProfile(profile);
    setEditContent(profile.content);
  };

  const handleSaveEdit = async () => {
    if (!editingProfile) return;
    setSaving(true);
    try {
      await tauri.updateProfile(editingProfile.id, editContent);
      setEditingProfile(null);
      // Re-fetch profiles to sync
      const allProfiles = await tauri.getProfiles();
      useRiptideStore.getState().setProfiles(allProfiles);
    } catch (error) {
      console.error('Failed to save profile:', error);
    } finally {
      setSaving(false);
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
            onClick={() => setShowShareUriModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
          >
            <Download size={14} />
            分享链接
          </button>
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
              <button
                onClick={() => handleEdit(profile)}
                className="p-1.5 bg-slate-800 hover:bg-slate-700 text-slate-400 rounded-lg transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
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

      {/* Share URI Modal */}
      {showShareUriModal && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 w-full max-w-lg shadow-2xl">
            <h3 className="text-base font-semibold text-slate-100 mb-3">
              从分享链接导入
            </h3>
            <p className="text-xs text-slate-500 mb-3">
              支持 ss://, trojan://, vless://, vmess://, hysteria2:// 链接
            </p>
            <textarea
              placeholder="粘贴分享链接..."
              value={shareUri}
              onChange={(e) => setShareUri(e.target.value)}
              rows={4}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 mb-4 font-mono focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all resize-none"
            />
            <div className="flex items-center justify-end gap-2">
              <button
                onClick={() => setShowShareUriModal(false)}
                className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 rounded"
              >
                取消
              </button>
              <button
                onClick={handleImportFromShareUri}
                className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              >
                导入
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

      {/* Edit Profile Modal */}
      {editingProfile && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 w-full max-w-2xl shadow-2xl max-h-[80vh] flex flex-col">
            <h3 className="text-base font-semibold text-slate-100 mb-3">
              编辑配置: {editingProfile.name}
            </h3>
            <textarea
              value={editContent}
              onChange={(e) => setEditContent(e.target.value)}
              rows={20}
              spellCheck={false}
              className="flex-1 w-full px-3 py-2 bg-slate-950 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 font-mono focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all resize-none"
            />
            <div className="flex items-center justify-end gap-2 mt-3">
              <button
                onClick={() => setEditingProfile(null)}
                className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 rounded"
              >
                取消
              </button>
              <button
                onClick={handleSaveEdit}
                disabled={saving}
                className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50"
              >
                {saving ? '保存中...' : '保存'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
