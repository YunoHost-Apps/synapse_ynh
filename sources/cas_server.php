<?php

/*
This is simple implementation of a CAS server to provide a SSO with synapse and Riot
The authentication mechanism is documented here: https://matrix.org/docs/spec/client_server/latest#sso-client-login

Note that it's not a full implementation of a CAS server, but just the minimum to work with synapse and Riot.

Mainly this CAS server will:
1. Authenticate the user from the authentication header from ssowat
2. Save the user authentication data in a php session
3. Redirect the user to the homeserver (synapse)
4. Answer to the homeserver if the user with a specific ticket number is authenticated and give his username.
*/

// Get the URL of the request
$base_url = "/_matrix/cas_server.php";
$url = explode('?', $_SERVER['REQUEST_URI'], 2)[0];

switch ($url) {
    // Request from the homeserver (synapse)
    case $base_url . "/proxyValidate":
        // Get the session created by the client request
        session_id($_GET['ticket']);
        session_start();
        // Check if this user was properly authenticated
        if ($_SESSION['user_authenticated']) {
            // Give the authentication information to the server
            ?>
                <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
                    <cas:authenticationSuccess>
                    <cas:user><?php echo $_SESSION['user']; ?></cas:user>
                    <cas:proxyGrantingTicket>PGTIOU-84678-8a9d...</cas:proxyGrantingTicket>
                    </cas:authenticationSuccess>
                </cas:serviceResponse>
            <?php
        } else {
            ?>
                <cas:serviceResponse xmlns:cas='http://www.yale.edu/tp/cas'>
                    <cas:authenticationFailure code="INVALID_TICKET">
                        ticket PT-1856376-1HMgO86Z2ZKeByc5XdYD not recognized
                    </cas:authenticationFailure>
                </cas:serviceResponse>
            <?php
        }
    break;

    // First request from the client
    case $base_url . "/login":
        // Generate a random number ticket which will be used by the client to authenticate to the server
        $ticket = bin2hex(random_bytes(50));

        // Use the Ticket number as the session ID.
        // This gives the possiblity in the next request from the server to find this session and the related information.
        session_id($ticket);
        session_start();

        // If the user is authenticated by ssowat save the username and set it as properly authenticated
        if (array_key_exists('REMOTE_USER', $_SERVER) && strlen($_SERVER['REMOTE_USER']) > 0) {
            $_SESSION['user_authenticated'] = true;
            $_SESSION['user'] = $_SERVER['REMOTE_USER'];

            header('Status: 302 Moved Temporarily', false, 302);
            header('Location: ' . $_GET['service'] . '&ticket=' . $ticket);
        } else {
            echo "Authentication failed.";
        }
        session_commit();
    break;

    case $base_url:
        header('Status: 302 Moved Temporarily', false, 302);
        header('Location: ' . $_GET['redirectUrl']);

    break;

    default:
        echo "Bad URL";
}
?>
