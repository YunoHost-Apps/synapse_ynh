location = /.well-known/matrix/server {
    return 200 '{"m.server": "{{ domain }}:{{ port_synapse_tls }}"}';
    default_type application/json;
    more_set_headers "Access-Control-Allow-Origin: *";
}

location = /.well-known/matrix/client {
    return 200 '{
        "m.homeserver": { "base_url": "https://{{ domain }}" },
        "im.vector.riot.jitsi": {"preferredDomain": "{{ jitsi_server }}"},
        "im.vector.riot.e2ee": {"default": {{ e2e_enabled_by_default_client_config }} },
        "org.matrix.msc4143.rtc_foci": [
            {
                "type": "livekit",
                "livekit_service_url": "https://{{ domain }}/livekit/jwt"
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

location = /.well-known/matrix/support {
    return 200 '{
        "contacts": [
            {%- if contact_admin_matrix_id | length > 0 or contact_admin_email | length > 0 %}
            {
                {%- if contact_admin_matrix_id | length > 0 %}
                "matrix_id": "{{ contact_admin_matrix_id }}",
                {%- endif %}
                {%- if contact_admin_email | length > 0 %}
                "email_address": "{{ contact_admin_email }}",
                {%- endif %}
                "role": "m.role.admin"
            }
            {%- endif %}
        ]
        {%- if contact_support_page | length > 0 %},
        "support_page": "{{ contact_support_page }}"
        {%- endif %}
    }';
}


# Workaround to fix false positive of the linter proxy_params_with_auth
