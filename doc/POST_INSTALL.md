To federate this app you need to add this line in your DNS configuration:

`_matrix._tcp.__DOMAIN__. 3600    IN      SRV     10 0 __PORT__SYNAPSE_TLS__ __DOMAIN__`

You also need to open the TCP port __PORT__SYNAPSE_TLS__ on your ISP box if it's not automatically done.

Your Synapse server also implements a Turnserver (for VoIP), to have this fully functional please read the 'Turnserver' section in the README available here: https://github.com/YunoHost-Apps/synapse_ynh .
