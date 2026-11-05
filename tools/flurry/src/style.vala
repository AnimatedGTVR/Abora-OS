namespace Flurry {
    // Kept in code so the app has no resource bundle to install.
    const string STYLE = """
.hero {
  padding: 28px 30px;
  border-radius: 18px;
  background-image: linear-gradient(135deg, alpha(#3584e4, 0.95), alpha(#2ec27e, 0.80));
  color: white;
}
.hero-title { font-size: 26pt; font-weight: 800; letter-spacing: -0.5px; }
.hero-subtitle { font-size: 12pt; opacity: 0.92; }
.source-chip {
  padding: 3px 10px;
  border-radius: 99px;
  background-color: alpha(white, 0.22);
  font-size: 10pt;
  font-weight: 600;
}
.source-chip.off { opacity: 0.65; }
.source-chip .chip-button { padding: 0 8px; min-height: 22px; color: white; font-weight: 700; }
.app-tile { padding: 14px 16px; }
.app-tile:hover { background-color: alpha(currentColor, 0.04); }
.source-badge {
  padding: 1px 7px;
  border-radius: 99px;
  font-size: 8.5pt;
  font-weight: 700;
  background-color: alpha(currentColor, 0.08);
}
.source-badge.source-nix { color: #1c71d8; background-color: alpha(#3584e4, 0.14); }
.source-badge.source-flatpak { color: #26a269; background-color: alpha(#33d17a, 0.14); }
.source-badge.source-snap { color: #c64600; background-color: alpha(#ff7800, 0.14); }
.source-badge.installed { color: white; background-color: #26a269; }
.details-header .title-1 { font-size: 24pt; }
.log-view { padding: 10px; font-size: 9pt; background: transparent; }
.monospace-subtitle .subtitle { font-family: monospace; }
""";
}
