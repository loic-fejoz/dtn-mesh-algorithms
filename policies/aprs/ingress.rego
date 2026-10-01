package dtn.aprs.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.aprs.constants
import data.dtn.aprs.helpers

# Décision par défaut : IGNORER / DROP
default decision := {
    "action": "DROP",
    "reason": "Default drop rule",
    "mutations": []
}

# 1. Livraison locale si la destination est le nœud local
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node",
    "mutations": []
} if {
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Règle Dire Wolf 6.1(b) : Rejeter tout paquet émis par le nœud local lui-même
decision := {
    "action": "DROP",
    "reason": "Packet originated from local station (Dire Wolf rule 6.1b)",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_own_packet(input.bundle, input.node)
}

# 3. Suppression de doublon (Dupe Suppression Cache de 30 secondes en APRS - Dire Wolf 6.2a)
decision := {
    "action": "DROP",
    "reason": "Duplicate packet detected in seen cache",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    helpers.is_duplicate(input.bundle, input.node.seen_cache)
}

# 4. Le nœud n'est pas configuré comme digipeater APRS
decision := {
    "action": "DROP",
    "reason": "Local node is not configured as an APRS digipeater",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater != true
}

# 5. Trajectoire APRS déjà épuisée (tous les sauts ont été consommés)
decision := {
    "action": "DROP",
    "reason": "APRS path trajectory is already exhausted",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    trajectory.active_hop_index >= count(trajectory.path_elements)
}

# 6. Règle Dire Wolf 6.3(c) : Rejet d'un alias dont le compte est déjà épuisé (N=0)
decision := {
    "action": "DROP",
    "reason": "Generic alias hop count exhausted (N=0, Dire Wolf rule 6.3c)",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_alias_hop(hop)
    helpers.get_remaining_count(hop) <= 0
}

# 7. Saut Strict : l'indicatif/EID correspond au nœud local (Dire Wolf 6.1c / 6.3a)
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Strict hop matched local node (%v)", [input.node.callsign]),
    "mutations": [
        {
            "block_type": 200,
            "operation": "MUTATE_APRS_PAYLOAD",
            "active_hop_index": trajectory.active_hop_index + 1,
            "updated_hop_index": trajectory.active_hop_index,
            "updated_hop": object.union(hop, {
                "completed": true,
                "digipeated": true,
                "serviced_by": input.node.callsign,
                "substituted_by": input.node.callsign
            }),
            "cache_hash": helpers.get_transaction_id(input.bundle)
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_strict_match(hop, input.node)
}

# 8. Saut Strict : adressé à un autre digipeater -> IGNORER (Dire Wolf 6.1f)
decision := {
    "action": "SKIP",
    "reason": sprintf("Strict hop addressed to another node (%v)", [helpers.get_target_id(hop)]),
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_strict_hop(hop)
    not helpers.is_strict_match(hop, input.node)
}

# 9. Recommandation Dire Wolf Section 10 : Trapping des alias excessifs (ex: WIDE3-3, WIDE4-4)
# Clampe l'alias pour un seul et unique relais afin de protéger le canal radio contre la saturation
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Trapped excessive alias %v clamped to single digipeat (Dire Wolf section 10)", [scope_name]),
    "mutations": [
        {
            "block_type": 200,
            "operation": "MUTATE_APRS_PAYLOAD",
            "active_hop_index": trajectory.active_hop_index + 1,
            "updated_hop_index": trajectory.active_hop_index,
            "updated_hop": object.union(hop, {
                "remaining_count": 0,
                "remaining_hops": 0,
                "completed": true,
                "digipeated": true,
                "serviced_by": input.node.callsign,
                "substituted_by": input.node.callsign
            }),
            "cache_hash": helpers.get_transaction_id(input.bundle)
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_alias_hop(hop)
    scope_name := helpers.get_scope_name(hop)
    helpers.get_remaining_count(hop) > 0
    trapped := object.get(input.node, "trapped_aliases", [])
    helpers.is_trapped_alias(scope_name, trapped)
}

# 10. Alias Générique : Dire Wolf 6.3(a) (N >= 2 décrémenté, insertion de l'indicatif)
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v decremented to %v (Dire Wolf rule 6.3a)", [scope_name, rem_count - 1]),
    "mutations": [
        {
            "block_type": 200,
            "operation": "MUTATE_APRS_PAYLOAD",
            "active_hop_index": trajectory.active_hop_index, # Reste sur cet alias pour les relais suivants
            "updated_hop_index": trajectory.active_hop_index,
            "updated_hop": object.union(hop, {
                "remaining_count": rem_count - 1,
                "remaining_hops": rem_count - 1,
                "serviced_by": input.node.callsign,
                "substituted_by": input.node.callsign
            }),
            "cache_hash": helpers.get_transaction_id(input.bundle)
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_alias_hop(hop)
    scope_name := helpers.get_scope_name(hop)
    rem_count := helpers.get_remaining_count(hop)
    rem_count > 1
    trapped := object.get(input.node, "trapped_aliases", [])
    not helpers.is_trapped_alias(scope_name, trapped)
    helpers.is_alias_supported(scope_name, input.node.supported_aliases)
}

# 11. Alias Générique : Dire Wolf 6.3(b) (N == 1, remplacé par l'indicatif, consommé)
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v fully consumed (Dire Wolf rule 6.3b)", [scope_name]),
    "mutations": [
        {
            "block_type": 200,
            "operation": "MUTATE_APRS_PAYLOAD",
            "active_hop_index": trajectory.active_hop_index + 1, # Consommé, passage au saut suivant
            "updated_hop_index": trajectory.active_hop_index,
            "updated_hop": object.union(hop, {
                "remaining_count": 0,
                "remaining_hops": 0,
                "completed": true,
                "digipeated": true,
                "serviced_by": input.node.callsign,
                "substituted_by": input.node.callsign
            }),
            "cache_hash": helpers.get_transaction_id(input.bundle)
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_alias_hop(hop)
    scope_name := helpers.get_scope_name(hop)
    rem_count := helpers.get_remaining_count(hop)
    rem_count == 1
    trapped := object.get(input.node, "trapped_aliases", [])
    not helpers.is_trapped_alias(scope_name, trapped)
    helpers.is_alias_supported(scope_name, input.node.supported_aliases)
}

# 12. Alias non supporté par ce digipeater (ex: WIDE3 non supporté et non trappé)
decision := {
    "action": "SKIP",
    "reason": sprintf("Alias %v is not supported by this digipeater", [scope_name]),
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_own_packet(input.bundle, input.node)
    not helpers.is_duplicate(input.bundle, input.node.seen_cache)
    input.node.is_digipeater == true
    trajectory := helpers.get_trajectory_payload(input.bundle)
    hop := helpers.get_active_hop(trajectory)
    helpers.is_alias_hop(hop)
    scope_name := helpers.get_scope_name(hop)
    helpers.get_remaining_count(hop) > 0
    trapped := object.get(input.node, "trapped_aliases", [])
    not helpers.is_trapped_alias(scope_name, trapped)
    not helpers.is_alias_supported(scope_name, input.node.supported_aliases)
}
