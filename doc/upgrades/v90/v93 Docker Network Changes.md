# Docker Network changes

In Docker Engine v28, there was a change that prevents NAT from working. ComputeStacks manages firewall and nat rules outside of docker, and docker's recent change created a new DROP rule in their iptable rules. This would prevent any exposed port, including sftp containers, from working.

In order to overcome this, you will need to rebuild all networks on a node. This will require the containers to be rebuilt as well.

Once this update has been deployed, navigate to Settings -> Regions -> (Manage for the individual availability zones). Then click 'Rebuild Container Networks'.

This process will:

1. Stop all running containers.
2. Delete the existing docker network.
3. Re-create the docker network with the appropriate flags.
4. Rebuild all running containers.

Any container that was previously stopped, will be removed from the node. Simply 'start' the container again in ComputeStacks to re-create it.

IP addresses will not change, and the security of the projects will remain in tact. Network access is managed upstream of Docker.

