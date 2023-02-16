#!/bin/bash
sudo apt update
sudo apt install nginx -y

cat <<EOF >> /var/www/html/index.html
<html>
<head>
<title>Hello World ${HOSTNAME} </title>
</head>
<body>
<h1>Hello World! ${HOSTNAME} </h1>
</body>
</html>
EOF
