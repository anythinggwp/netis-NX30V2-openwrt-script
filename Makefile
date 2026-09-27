ROUTER=
deploy-backup-script:
	scp -O backup_en.sh useradmin@$(ROUTER):/tmp/backup_en.sh