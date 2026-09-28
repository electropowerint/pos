/* ============================================================
   NovaPOS — Firebase (Firestore) init  ·  firebase-init.js
   ES module. Initializes the Firebase app + Firestore and
   exposes a small sync API on `window.FBSync`, which
   app.js (classic script) uses.
   ------------------------------------------------------------
   Data model: collection `appdata`, single doc `snapshot`
   { savedAt: <number>, data: { settings, invoices, ... } }
   The web app + a future Flutter app will share this doc.
   ============================================================ */
import { initializeApp } from "https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js";
import { getFirestore, doc, getDoc, setDoc } from "https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyCSXAx72uSMJ45VB2bn6pygXi8MGXod83Q",
  authDomain: "eppos-41139.firebaseapp.com",
  projectId: "eppos-41139",
  storageBucket: "eppos-41139.firebasestorage.app",
  messagingSenderId: "583932968743",
  appId: "1:583932968743:web:d34b15f76ed39e8a43b302",
  measurementId: "G-9PKN4D2FBD"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const SNAP = () => doc(db, "appdata", "snapshot");

window.FBSync = {
  backend: "firebase",
  projectId: firebaseConfig.projectId,
  async get() {
    const s = await getDoc(SNAP());
    return s.exists() ? s.data() : null;
  },
  async set(payload) {
    await setDoc(SNAP(), payload);
  }
};

window.dispatchEvent(new Event("novapos-fb-ready"));
