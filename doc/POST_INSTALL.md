To federate this app you need to add this line in your DNS configuration:

` _matrix._tcp.$domain. 3600    IN      SRV     10 0 $port_synapse_tls $domain`

You also need to open the TCP port $port_synapse_tls on your ISP box if it's not automatically done.

Your Synapse server also implements a turnserver (for VoIP), to have this fully functional please read the 'Turnserver' section in the README available here: https://github.com/YunoHost-Apps/synapse_ynh .
