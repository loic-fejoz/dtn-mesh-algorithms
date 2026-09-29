package dtn.cgr.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.cgr.constants

# Vérifie si le bundle est un message de signalisation CGR (Contact Plan)
is_cgr_control(bundle) if {
    bundle.primary.destination == constants.cgr_broadcast_eid
}

is_cgr_control(bundle) if {
    contains(bundle.primary.destination, "/cgr")
}

# Vérifie si la destination correspond au nœud local
is_local_destination(destination, node) if {
    destination == node.local_eid
}

# Vérifie si une fenêtre de contact planifié est actuellement ouverte
is_contact_active(contact, current_time_ms) if {
    contact != null
    start_time := object.get(contact, "start_time_ms", 0)
    end_time := object.get(contact, "end_time_ms", 0)
    current_time_ms >= start_time
    current_time_ms <= end_time
}

# Récupère le meilleur chemin CGR vers la destination calculé dans le graphe spatio-temporel
default get_cgr_path(_, _) := null

get_cgr_path(destination, cgr_routes) := path if {
    cgr_routes != null
    path := object.get(cgr_routes, destination, null)
    path != null
}

get_cgr_path(destination, cgr_routes) := path if {
    cgr_routes != null
    not object.get(cgr_routes, destination, null)
    some key, val in cgr_routes
    contains(destination, key)
    path := val
}

# Vérifie si un chemin CGR est viable pour le bundle :
# 1. Le temps d'arrivée au plus tôt (EDT) n'excède pas l'expiration du bundle
# 2. La capacité restante de la fenêtre de contact est suffisante
is_path_viable(path, bundle, current_time_ms) if {
    path != null
    bundle_size := object.get(bundle, "total_size_bytes", 1024)
    remaining_cap := object.get(path, "remaining_capacity_bytes", 0)
    remaining_cap >= bundle_size
    
    creation_time := bundle.primary.creation_timestamp.time
    lifetime := bundle.primary.lifetime
    expiry_time := creation_time + lifetime
    
    edt := object.get(path, "earliest_delivery_time_ms", 0)
    edt <= expiry_time
}

# Vérifie si l'émetteur figure dans la blacklist du nœud
is_source_blacklisted(source_eid, node) if {
    base_helpers.is_source_blacklisted(source_eid, node)
}
