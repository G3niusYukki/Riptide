import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Layout } from './components/Layout';
import { Dashboard } from './components/Dashboard';
import { Proxies } from './components/Proxies';
import { Profiles } from './components/Profiles';
import { Rules } from './components/Rules';
import { Connections } from './components/Connections';
import { SettingsPage } from './components/Settings';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Dashboard />} />
          <Route path="proxies" element={<Proxies />} />
          <Route path="profiles" element={<Profiles />} />
          <Route path="rules" element={<Rules />} />
          <Route path="connections" element={<Connections />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
