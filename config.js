// ================================================================
// TREZO COMMERCE — Configuration (À REMPLIR avant déploiement)
// Supabase → votre projet → Project Settings → API :
//  - "Project URL"      -> url
//  - "anon public" key  -> anonKey  (elle est conçue pour être publique)
//
// edition       : 'commerce' (cette app gère ventes, stocks, caisse…)
// urlCommerce   : URL de déploiement de Trezo Commerce
// urlServices   : URL de déploiement de Trezo Services
//   -> permettent la bascule BUSINESS (un compte, deux espaces, SSO)
// ================================================================
window.TREZO_CONFIG = {
  url: "https://VOTRE-PROJET.supabase.co",
  anonKey: "COLLEZ_ICI_LA_CLE_ANON_PUBLIC",
  edition: "commerce",
  urlCommerce: "",   // ex. "https://commerce.trezo.app"  (laisser vide si non déployé)
  urlServices: ""    // ex. "https://services.trezo.app"
};
