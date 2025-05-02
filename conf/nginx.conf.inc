location = /.well-known/matrix/server {
    return 200 '{"m.server": "__DOMAIN__:__PORT_SYNAPSE_TLS__"}';
    default_type application/json;
    more_set_headers "Access-Control-Allow-Origin: *";
}

location = /.well-known/matrix/client {
    return 200 '{
        "m.homeserver": { "base_url": "https://__DOMAIN__" },
        "im.vector.riot.jitsi": {"preferredDomain": "__JITSI_SERVER__"},
        "im.vector.riot.e2ee": {"default": __E2E_ENABLED_BY_DEFAULT_CLIENT_CONFIG__ },
        "org.matrix.msc4143.rtc_foci": [
            {
                "type": "livekit",
                "livekit_service_url": "https://__DOMAIN__/livekit/jwt"
            },
            {
                "type": "nextgen_new_foci_type",
                "props_for_nextgen_foci": "val"
            }
        ]
    }';
    default_type application/json;
    more_set_headers "Access-Control-Allow-Origin: *";
}
