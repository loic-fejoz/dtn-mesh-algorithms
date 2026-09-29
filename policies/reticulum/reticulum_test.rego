package dtn.reticulum_test

import future.keywords.if

import data.dtn.reticulum.constants
import data.dtn.reticulum.contact
import data.dtn.reticulum.ingress
import data.dtn.reticulum.storage

mock_node := {
    "local_eid": "dtn://node-local/",
    "reticulum_destination_hash": "a1b2c3d4e5f60718293a4b5c6d7e8f90",
    "blacklist_sources": ["dtn://evil-spammer/"],
    "seen_cache": [
        ["dtn://source-seen/", 1000, 1]
    ],
    "routing_table": {
        "dtn://rns/dest1/": {
            "destination_hash": "dest1",
            "next_hop_eid": "dtn://relay-node-1/",
            "hops": 2,
            "expires_at_ms": 5000000
        },
        "dest2": {
            "destination_hash": "dest2",
            "next_hop_eid": "dtn://relay-node-2/",
            "hops": 4,
            "expires_at_ms": 5000000
        },
        "expired-dest": {
            "destination_hash": "expired-dest",
            "next_hop_eid": "dtn://relay-node-1/",
            "hops": 1,
            "expires_at_ms": 1000 # Déjà expiré à current_time = 2000
        }
    },
    "enable_path_requests": true
}

mock_bundle(src, dest, lifetime, hop_count, hop_limit) := {
    "primary": {
        "source": src,
        "destination": dest,
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": lifetime,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10,
            "hop_count": hop_count,
            "hop_limit": hop_limit
        }
    ]
}

# 1. Ingress : Livraison locale si la destination correspond à l'EID local
test_reticulum_ingress_local_delivery_by_eid if {
    bundle := mock_bundle("dtn://sender/", "dtn://node-local/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# 2. Ingress : Livraison locale si l'URI contient le hash Reticulum local (16 octets)
test_reticulum_ingress_local_delivery_by_hash if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/a1b2c3d4e5f60718293a4b5c6d7e8f90/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# 3. Ingress : Rejet immédiat si la source est blacklistée
test_reticulum_ingress_blacklisted_source if {
    bundle := mock_bundle("dtn://evil-spammer/", "dtn://rns/target/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Source EID is blacklisted on this node"
}

# 4. Ingress : Rejet si la durée de vie est expirée
test_reticulum_ingress_expired if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/target/", 1000, 0, 10) # Expire à 2000
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2500
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 5. Ingress : Rejet si le Hop Count Block (Type 10) atteint sa limite
test_reticulum_ingress_hop_limit_reached if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/target/", 3600000, 5, 5) # 5+1 > 5
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Hop limit exceeded (Hop Count Block Type 10)"
}

# 6. Ingress : Découverte d'un nouveau chemin via une annonce Reticulum
test_reticulum_ingress_announce_new_route if {
    bundle := mock_bundle("dtn://rns/new-dest/", constants.announce_broadcast_eid, 3600000, 1, 64)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"peer_eid": "dtn://neighbor-gateway/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_ANNOUNCE"
    decision.mutations[0].operation == "UPDATE_ROUTING_TABLE"
    decision.mutations[0].destination_hash == "dtn://rns/new-dest/"
    decision.mutations[0].next_hop == "dtn://neighbor-gateway/"
    decision.mutations[0].hops == 2
}

# 7. Ingress : Mise à jour d'un chemin existant si la nouvelle annonce est plus courte
test_reticulum_ingress_announce_shorter_path if {
    # dest2 avait 4 sauts dans mock_node. Nouvelle annonce arrive avec 1 saut (+1 local = 2 sauts)
    bundle := mock_bundle("dest2", constants.announce_broadcast_eid, 3600000, 1, 64)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"peer_eid": "dtn://faster-relay/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_ANNOUNCE"
    decision.mutations[0].next_hop == "dtn://faster-relay/"
    decision.mutations[0].hops == 2
}

# 8. Ingress : Ignorer la mise à jour si la nouvelle annonce a un chemin plus long
test_reticulum_ingress_announce_longer_path_ignored if {
    # dest2 a 4 sauts. Nouvelle annonce arrive avec 6 sauts (+1 local = 7)
    bundle := mock_bundle("dest2", constants.announce_broadcast_eid, 3600000, 6, 64)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"peer_eid": "dtn://slower-relay/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_ANNOUNCE_NO_UPDATE"
}

# 9. Contact : Contact direct avec la destination finale
test_reticulum_contact_direct_destination if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/final-dest/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://rns/final-dest/",
            "is_broadcast": false
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_DIRECT"
}

# 10. Contact : Rediffusion en broadcast des annonces Reticulum
test_reticulum_contact_announce_broadcast if {
    bundle := mock_bundle("dtn://rns/new-dest/", constants.announce_broadcast_eid, 3600000, 0, 64)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://broadcast/",
            "is_broadcast": true
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_BROADCAST"
}

# 11. Contact : Acheminement vers le prochain saut exact indiqué dans la table de routage
test_reticulum_contact_forward_matching_next_hop if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/dest1/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node-1/", # Correspond au next-hop pour dest1
            "is_broadcast": false
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_NEXT_HOP"
}

# 12. Contact : Ignorer un pair qui n'est pas le prochain saut désigné
test_reticulum_contact_skip_non_next_hop_peer if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/dest1/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node-2/", # dest1 passe par relay-node-1, pas 2 !
            "is_broadcast": false
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    contains(decision.reason, "is not the designated next-hop")
}

# 13. Contact : Destination inconnue -> Rétention en stockage (Store-Carry-and-Forward)
test_reticulum_contact_skip_unknown_destination if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/unknown-target/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node-1/",
            "is_broadcast": false
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    contains(decision.reason, "No valid next-hop route in table")
}

# 14. Contact : Route expirée -> Rétention en stockage
test_reticulum_contact_skip_expired_route if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/expired-dest/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node-1/",
            "is_broadcast": false
        },
        "current_dtn_time_ms": 2000 # Route expirée à 1000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    contains(decision.reason, "No valid next-hop route in table")
}

# 15. Storage : Élimination périodique des bundles dont la durée de vie a expiré
test_reticulum_storage_drop_expired if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/dest1/", 1000, 0, 10) # Expire à 2000
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 3000,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Lifetime expired during storage audit"
}

# 16. Storage : Déclenchement d'une découverte de chemin (Path Request) si la route est inconnue
test_reticulum_storage_trigger_path_request if {
    bundle := mock_bundle("dtn://sender/", "dtn://rns/unknown-target/", 3600000, 0, 10)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as inp
    decision.action == "RETAIN_AND_REQUEST_PATH"
    decision.mutations[0].operation == "TRIGGER_PATH_REQUEST"
}
