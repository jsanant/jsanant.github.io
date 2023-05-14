pull:
	git pull origin main

push:
	git pull origin main
	git add --all
	git commit --m "automated push"
	git push origin main