all:
	stow --verbose --target=$$HOME --restow stowfiles/

delete:
	stow --verbose --target=$$HOME --delete stowfiles/
