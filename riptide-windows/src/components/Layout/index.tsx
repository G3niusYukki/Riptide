import { Outlet } from 'react-router-dom';
import { Sidebar } from '../Sidebar';
import { Header } from './Header';
import { ToastContainer } from '../Toast';

export function Layout() {
  return (
    <div className="flex h-screen bg-slate-950 text-slate-200">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header />
        <main className="flex-1 overflow-auto p-6">
          <Outlet />
        </main>
      </div>
      <ToastContainer />
    </div>
  );
}
