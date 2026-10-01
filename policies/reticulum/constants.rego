package dtn.reticulum.constants

# Longueur en octets d'une adresse de destination Reticulum (128 bits)
hash_length_bytes := 16

# Limite maximale de propagation des annonces
max_announce_hops := 128

# Durée de validité par défaut d'un chemin découvert via une annonce (24 heures)
default_path_ttl_ms := 86400000

# EID réservé pour la diffusion des annonces Reticulum
announce_broadcast_eid := "dtn://rns/announce"

# Actions de routage
action_forward_direct := "FORWARD_DIRECT"
action_forward_next_hop := "FORWARD_NEXT_HOP"
action_forward_broadcast := "FORWARD_BROADCAST"
action_deliver_local := "DELIVER_LOCAL"
action_skip := "SKIP"
action_drop := "DROP"
action_accept := "ACCEPT"
