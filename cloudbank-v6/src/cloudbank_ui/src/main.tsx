import { createRoot } from 'react-dom/client';
import { MockStoreProvider } from './model';
import { App } from './App';
import './styles.css';

createRoot(document.getElementById('root')!).render(<MockStoreProvider><App /></MockStoreProvider>);
