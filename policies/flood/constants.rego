package dtn.flood.constants

# Type de bloc d'extension de routage mesh (CDDL)
block_type_mesh_routing := 200

# Identifiants d'algorithmes
algo_spray_and_wait := 2
algo_meshtastic_flooding := 4

# Modes Spray & Wait
spray_mode_source := 1 # Source Spray (1 copie par relais rencontré)
spray_mode_binary := 2 # Binary Spray (L/2 copies distribuées récursivement)

# Phases Spray & Wait
phase_spray := 1 # Phase de pulvérisation (L > 1)
phase_wait := 2  # Phase d'attente passive (L == 1, livraison directe uniquement)

# Paramètres de temporisation Meshtastic (Backoff selon SNR)
# En Meshtastic, un nœud ayant reçu avec un SNR plus faible (plus distant)
# retransmet plus vite pour maximiser l'expansion géographique du réseau.
meshtastic_base_backoff_ms := 200
meshtastic_snr_factor_ms := 50
