#!/bin/bash
#
# Script de déploiement de GLPI sur Debian avec Nginx
#
 
function warn(){
    echo -e '\e[31m'$1'\e[0m';
}
function info(){
    echo -e '\e[36m'$1'\e[0m';
}
 
# Fonction pour vérifier les erreurs
function check_error() 
{
    if [ $? -ne 0 ]; then
        echo "Erreur: $1"
        exit 1
    fi
}
 
function root_check()
{
# Vérification des privilèges root
if [ "$(id -u)" != "0" ]; 
then
   	warn "Ce script doit être lancé en tant que root" >&2
	exit 1
fi
}
 
function welcome_message()
{
info "=======> Script d'installation de GLPI <======="
echo "Ce script permet d'installer et de configurer Nginx, GLPI et MySQL sur votre machine."
warn "Ce script est prévu pour être executé sur une distribution Debian 11/12/13."
echo
read -p "Souhaitez-vous procéder à l'installation? [oui/non] : " confirm
echo
if [ "$confirm" == "oui" ]; then
	info "Début de l'installation…"
	sleep 1
elif [ "$confirm" == "non" ]; then
	info "Au revoir !"
	sleep 1
	exit 1
else
	warn "Réponse invalide…"
	sleep 1
	exit 1
fi
} 
 
function check_version()
{
echo
info "Vérification de la version de la distribution..."
sleep 1

# Vérifier si lsb_release est disponible
if ! command -v lsb_release &> /dev/null; then
    warn "lsb_release n'est pas installé. Installation..."
    apt install -y lsb-release
    check_error "Impossible d'installer lsb-release"
fi

# Versions de Debian acceptables
DEBIAN_VERSIONS=("11" "12" "13")

# Récupération du nom de la distribution
DISTRO=$(lsb_release -is)
check_error "Impossible de récupérer le nom de la distribution"

# Récupération de la version de la distribution
VERSION=$(lsb_release -rs)
check_error "Impossible de récupérer la version de la distribution"

if [ "$DISTRO" == "Debian" ]; then
        if [[ " ${DEBIAN_VERSIONS[*]} " == *" $VERSION "* ]]; then
        info "Votre version ($DISTRO $VERSION) est compatible."
        else
        warn "Votre version ($DISTRO $VERSION) n'est pas compatible"
        exit 1
        fi
else
    warn "Ce script est prévu pour Debian uniquement"
    exit 1
fi
}
 
function ask_credentials()
{
echo
read -ep "Veuillez entrer le nom de la base de données à créer (Ex : glpi) : " GLPI_DB_NAME ; echo
read -ep "Veuillez entrer le nom d'utilisateur de la base de données GLPI (Ex : glpiuser) : " GLPI_DB_USER ; echo
 
read -esp "Veuillez entrer le mot de passe de l'utilisateur root de la base de données : " MYSQL_ROOT_PASSWORD ; echo
read -esp "Veuillez confirmer le mot de passe de l'utilisateur root de la base de données : " MYSQL_ROOT_PASSWORD2 ; echo
 
while [ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_ROOT_PASSWORD2" ]
do
	echo "Les mots de passes ne correspondent pas. Veuillez réessayer."
	echo
        read -esp "Veuillez entrer le mot de passe de l'utilisateur root de la base de données : " MYSQL_ROOT_PASSWORD ; echo
        read -esp "Veuillez confirmer le mot de passe de l'utilisateur root de la base de données : " MYSQL_ROOT_PASSWORD2 ; echo
done
 
read -esp "Veuillez entrer le mot de passe de l'utilisateur $GLPI_DB_USER de la base de données : " GLPI_DB_PASSWORD ; echo
read -esp "Veuillez confirmer le mot de passe de l'utilisateur $GLPI_DB_USER de la base de données : " GLPI_DB_PASSWORD2 ; echo
 
while [ "$GLPI_DB_PASSWORD" != "$GLPI_DB_PASSWORD2" ]
do
	echo "Les mots de passes ne correspondent pas. Veuillez réessayer."
	echo 
       	read -esp "Veuillez entrer le mot de passe de l'utilisateur $GLPI_DB_USER de la base de données : " GLPI_DB_PASSWORD ; echo
        read -esp "Veuillez confirmer le mot de passe de l'utilisateur $GLPI_DB_USER de la base de données : " GLPI_DB_PASSWORD2 ; echo
done
}
 
function php_version()
{
if [ "$VERSION" == "13" ]; then
        PHP_VERSION="8.3"  # Ajustement pour Debian 13
elif [ "$VERSION" == "12" ]; then
        PHP_VERSION="8.2"       
elif [ "$VERSION" == "11" ]; then
        PHP_VERSION="7.4"
fi
}
 
function system_update()
{
echo
info "Mise à jour du système..."
sleep 1
apt update && apt upgrade -y
check_error "Impossible de mettre à jour le système"
}
 
function install_packages()
{
echo
info "Installation des paquets..."
sleep 1
apt install -y \
nginx \
mariadb-server \
php-fpm \
php-mysql \
php-curl \
php-gd \
php-intl \
php-pear \
php-imagick \
php-imap \
php-memcache \
php-pspell \
php-tidy \
php-xmlrpc \
php-mbstring \
php-ldap \
php-cas \
php-apcu \
php-json \
php-xml \
php-cli \
php-zip \
wget \
unzip

# Essayer d'installer php-imap (optionnel, peut ne pas être disponible sur Debian 13)
apt install -y php-imap 2>/dev/null || warn "php-imap non disponible (optionnel)"

systemctl enable mariadb
systemctl enable nginx
check_error "Impossible d'installer les dépendances principales"
}
 
function mariadb_configuration()
{
echo
info "Configuration de MariaDB..."

# Essayer de définir le mot de passe root (si connexion via socket)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'" || true

# Nettoyage initial (suppression utilisateurs anonymes, base test, etc.)
mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
FLUSH PRIVILEGES;
EOF

# Maintenant se connecter avec le mot de passe root pour créer la base et l'utilisateur GLPI
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE $GLPI_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$GLPI_DB_USER'@'localhost' IDENTIFIED BY '$GLPI_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $GLPI_DB_NAME.* TO '$GLPI_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
check_error "Impossible de configurer MariaDB"
}
 
 
function glpi_install()
{
echo
info "Téléchargement et installation de GLPI..."
wget https://github.com/glpi-project/glpi/releases/download/10.0.16/glpi-10.0.16.tgz
check_error "Impossible de télécharger GLPI"

tar xzf glpi-10.0.16.tgz -C /var/www/
check_error "Impossible d'extraire l'archive GLPI"

rm glpi-10.0.16.tgz

# Configuration des permissions
info "Configuration des permissions..."
chown -R www-data:www-data /var/www/glpi
chmod -R 755 /var/www/glpi
chmod -R 775 /var/www/glpi/var
chmod -R 775 /var/www/glpi/files
chmod -R 775 /var/www/glpi/config
check_error "Impossible de configurer les permissions"
}

 
function nginx_configuration()
{
echo
info "Configuration de Nginx..."
# Essayer de définir le mot de passe root (si connexion via socket)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'" || true

# Nettoyage initial (suppression utilisateurs anonymes, base test, etc.)
mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
FLUSH PRIVILEGES;
EOF

# Maintenant se connecter avec le mot de passe root pour créer la base et l'utilisateur GLPI
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE $GLPI_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$GLPI_DB_USER'@'localhost' IDENTIFIED BY '$GLPI_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $GLPI_DB_NAME.* TO '$GLPI_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
check_error "Impossible de configurer MariaDB"
}
 
function reload_services()
{
echo
info "Redémarrage des services..."

# Activer et démarrer PHP-FPM correct si nécessaire
systemctl enable php$PHP_VERSION-fpm || true
systemctl is-active --quiet php$PHP_VERSION-fpm || systemctl start php$PHP_VERSION-fpm

systemctl is-active --quiet nginx || systemctl start nginx

systemctl restart php$PHP_VERSION-fpm
systemctl restart nginx
check_error "Impossible de redémarrer les services"

info "Services redémarrés avec succès !"
}
 
function display_credentials()
{
echo
info "=======> Détails d'installation GLPI <======="
warn "Il est important de noter ces informations. Si vous les perdez, elles seront irrécupérables."
info "==> GLPI :"
info "UTILISATEUR	-  MOT DE PASSE		-  ACCES"
info "glpi		-  glpi			-  Compte Administrateur"
info "tech		-  tech			-  Compte technique"
info "normal		-  normal		-  Compte normal"
info "post-only		-  post-only		-  Compte Helpdesk"
echo
info "Vous pouvez vous connecter et configurer GLPI à cette adresse :"
info "http://adresse_ip_du_serveur"
echo
info "==> Base de données :"
info "Mot de passe root :			$MYSQL_ROOT_PASSWORD"
info "Mot de passe utilisateur $GLPI_DB_USER :	$GLPI_DB_PASSWORD"
info "Nom base de données GLPI :		$GLPI_DB_NAME"
info "<===========================================>"
}
 
root_check
welcome_message
check_version
ask_credentials
php_version
system_update
install_packages
mariadb_configuration
glpi_install
nginx_configuration
reload_services
display_credentials