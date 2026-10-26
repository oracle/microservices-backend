# Secure MicroTx on OKE OBaaS

Use the single [`secure-microtx-workflows.sh`](secure-microtx-workflows.sh)
operator command to configure authentication between the existing CloudBank
`azn-server` and the MicroTx components installed by OBaaS.

Complete Chapter 1 of
[`azn-server-runbook.md`](../../obaas/azn-server-runbook.md), deploy
`azn-server`. The unified deployment enables and verifies MicroTx authentication
automatically on both first deployment and redeploy. To reapply it separately:

```bash
cd ./cloudbank-v6
./deploy/microtx/oke-obaas/secure-microtx-workflows.sh --enable
```

The script obtains its target, URLs, and generated OAuth credential from the `.env` in `cloudbank-v6` directory. It validates the live target and all Kubernetes patches,
shows the resolved non-sensitive deployment target, asks for confirmation, and
then applies and verifies the configuration. It does not install or upgrade
OBaaS and does not create or update workflow definitions.

For the complete procedure, re-deployment guidance, Console access, and the
development-only authentication removal command, see
[`secure-microtx-azn.md`](secure-microtx-azn.md).
