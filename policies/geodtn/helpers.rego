package dtn.geodtn.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.geodtn.constants

# Récupère le bloc d'extension de routage mesh (Type 200)
get_mesh_routing_block(bundle) := blk if {
    some b in object.get(bundle, "extension_blocks", [])
    b.block_type == constants.block_type_mesh_routing
    blk := b
}

# Récupère la primitive spatial_scope du bloc d'extension (facette 5 du Type 200)
default get_spatial_scope(_) := null

get_spatial_scope(bundle) := scope if {
    blk := get_mesh_routing_block(bundle)
    scope := object.get(blk, "spatial_scope", null)
    scope != null
}

# Vérifie si le bundle est une diffusion géographique (Geocast)
is_geocast(bundle) if {
    scope := get_spatial_scope(bundle)
    scope != null
    radius := object.get(scope, "radius_deg", object.get(scope, "radius_meters", 0))
    radius > 0
}

# Calcul de distance euclidienne au carré entre deux coordonnées
squared_distance(lat1, lon1, lat2, lon2) := ((lat2 - lat1) * (lat2 - lat1)) + ((lon2 - lon1) * (lon2 - lon1))

# Vérifie si des coordonnées se situent à l'intérieur du périmètre Geocast
is_inside_perimeter(node_lat, node_lon, target_lat, target_lon, radius) if {
    dist_sq := squared_distance(node_lat, node_lon, target_lat, target_lon)
    dist_sq <= (radius * radius)
}

# Vérifie si le nœud local est destinataire légitime du bundle :
# 1. Correspondance exacte d'EID unicast
is_local_destination(bundle, node) if {
    bundle.primary.destination == node.local_eid
}

# 2. Diffusion Geocast et le nœud local est physiquement présent dans la zone cible
is_local_destination(bundle, node) if {
    is_geocast(bundle)
    scope := get_spatial_scope(bundle)
    coords := object.get(node, "coordinates", null)
    coords != null
    radius := object.get(scope, "radius_deg", 0.01)
    is_inside_perimeter(coords.lat, coords.lon, scope.center_lat_deg, scope.center_lon_deg, radius)
}

# Vérifie si le pair est strictement plus proche de la cible que le nœud local (Greedy Forwarding)
is_peer_closer(peer_coords, my_coords, target_lat, target_lon) if {
    peer_coords != null
    my_coords != null
    peer_dist_sq := squared_distance(peer_coords.lat, peer_coords.lon, target_lat, target_lon)
    my_dist_sq := squared_distance(my_coords.lat, my_coords.lon, target_lat, target_lon)
    peer_dist_sq < my_dist_sq
}

# Vérifie si la source est blacklistée
is_source_blacklisted(source_eid, node) if {
    base_helpers.is_source_blacklisted(source_eid, node)
}
