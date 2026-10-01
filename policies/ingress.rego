package dtn.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants
import data.dtn.helpers

# Décision par défaut : REJECT / DROP
default decision := {
    "action": "DROP",
    "reason_code": 6, # constants.reason_no_known_route
    "reason": "Default drop rule",
    "generate_status_report": false,
    "mutations": []
}

# 0. Rejet immédiat si la source est blacklistée par le nœud local (Anti-Spam / DoS / Isolation)
# Ne génère aucun rapport d'état pour éviter d'amplifier le trafic de spam
decision := {
    "action": "DROP",
    "reason_code": constants.reason_depleted_storage,
    "reason": "Source EID is blacklisted on this node",
    "generate_status_report": false,
    "mutations": []
} if {
    helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
}

# 1. Le bundle est destiné au nœud local (RFC 9171 Section 5.3 : Step 1)
# La livraison locale a priorité sur l'expiration du hop count de transit
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination endpoint matches local node",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Expiration de la Lifetime à l'arrivée
decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime has expired upon arrival",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Dépassement de la limite de sauts (Hop Count Block - RFC 9171 Section 4.3.3)
# À la réception, le hop count est incrémenté de 1. S'il devient égal ou supérieur au hop_limit,
# le bundle en transit doit être supprimé.
decision := {
    "action": "DROP",
    "reason_code": constants.reason_hop_limit_exceeded,
    "reason": "Hop limit exceeded after ingress hop increment",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    helpers.will_exceed_hop_limit(input.bundle)
}

# 4. Ingress valide : acceptation pour stockage et acheminement ultérieur
# Application de la mutation obligatoire : incrémenter le hop_count de 1
decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted for forwarding / storage",
    "generate_status_report": false,
    "mutations": [
        {
            "block_type": constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hop_block.hop_count + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.will_exceed_hop_limit(input.bundle)
    hop_block := helpers.get_hop_count_block(input.bundle)
}

# 5. Ingress valide pour un bundle ne contenant pas de Hop Count Block
decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted (no hop count block)",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.get_hop_count_block(input.bundle)
}
