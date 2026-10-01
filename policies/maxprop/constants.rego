package dtn.maxprop.constants

# Facteur de pénalisation fluide de saut (0.01 par saut)
hop_penalty_factor := 0.01

# Epsilon résiduel pour éviter la singularité du logarithme à probabilité nulle
epsilon := 0.001

# Préfixe de diffusion des messages de contrôle MaxProp
maxprop_broadcast_eid := "dtn://broadcast/maxprop"

# Coût infini de chemin non connecté
cost_infinity := 9999.0
