echo "Creating mysql user bhima"

password=$(openssl rand -hex 18)
database="bhima"

echo "Password created: $password"

# only the
mysql -e "CREATE USER bhima IDENTIFIED BY '$password';"
mysql -e "GRANT ALL PRIVILEGES ON $database.* TO bhima;"

# needed for mysqldump
mysql -e "GRANT SELECT, SHOW VIEW, EXECUTE, TRIGGER, EVENT, ALTER ROUTINE ON $database.* TO bhima;"

# write the user credentials to the disk
echo "

[mysql]
hostname = 127.0.0.1
user = bhima
password = $password

" >>~/.my.cnf
