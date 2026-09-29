package dtn.prophet.constants

# Type de bloc d'extension de routage mesh (CDDL)
block_type_mesh_routing := 200

# Paramètres standards PRoPHET (RFC 6693)
# P_encounter_max : valeur par défaut pour une première rencontre directe
p_encounter_max := 0.75

# Facteur de vieillissement temporel gamma (0 < gamma < 1)
# Chaque unité de temps écoulée réduit la prévisibilité : P = P * (gamma ^ k)
default_gamma := 0.98

# Facteur d'échelle de transitivité beta (0 <= beta <= 1)
# P(a, c) = P(a, c) + (1 - P(a, c)) * P(a, b) * P(b, c) * beta
default_beta := 0.25

# Marge minimale d'amélioration pour autoriser le forwarding
default_forward_margin := 0.0
