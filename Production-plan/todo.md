# EC2 Stack TODO

## Pending
- [ ] Enable Python task runner — install `python3` in n8n Dockerfile, rebuild & push to ECR, restart n8n on EC2
- [ ] Add `N8N_TRUST_PROXY=true` to local docker-compose.yml (same express-rate-limit fix)
- [ ] Consider switching N8N_LOG_LEVEL from `info` to `warn` on EC2 to reduce noise
- [ ] Byobu installed from source on EC2 — won't survive instance replacement; add to userdata.sh.tpl if desired
- [ ] zsh/oh-my-zsh installed on EC2 — same as above, add to userdata.sh.tpl to persist across redeploys

## Completed
- [x] Fix `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR` — set `N8N_PROXY_HOPS=1` and `N8N_TRUST_PROXY=true`
- [x] Fix Terraform `n8n_proxy_hops` logic — always `1` (nginx edge is a proxy even without ALB)
- [x] Install zsh, oh-my-zsh, byobu, autocomplete plugins on EC2
- [x] Stack healthy — postgres, n8n, nginx edge all running
- [x] Workflows activating correctly on EC2
- [x] Execute data migration from local stack to EC2
