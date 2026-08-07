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
  url: "https://nxntmhqtrffbnjvozidt.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54bnRtaHF0cmZmYm5qdm96aWR0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNTQwMjEsImV4cCI6MjA5ODkzMDAyMX0.YPqgHcwbtJ6jh-T2LXEFjI1CfgyGow1_BwbUOF0RaRk",
  edition: "commerce",
 urlCommerce: "https://trezo-cloud.pages.dev/",
  urlServices: "https://trezo-presta.pages.dev/"
};
