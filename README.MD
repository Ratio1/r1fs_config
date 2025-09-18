# Prerequisites
To generate a swarm key you have to run the following command:
```bash
go install github.com/Kubuxu/go-ipfs-swarm-key-gen/ipfs-swarm-key-gen@latest
```
Add GO to your PATH if it is not already set. You can do this by adding the following line to your shell configuration file (e.g., `~/.bashrc`, `~/.zshrc`):
```bash
export PATH=$PATH:$(go env GOPATH)/bin
```

Then generate a swarm key with:
```bash
ipfs-swarm-key-gen > swarm.key
```

Make swarm key base64 encoded:
```bash
cat swarm.key | base64 -w0
```


## Prepare the certificate
```bash
gzip -c mycert.pem | base64 -w0 > mycert.b64
```

Decode it: 
```bash
cat mycert.b64 | base64 -d | gunzip > mycert.pem
```