library(phytools)
library(paco)
library(magrittr)
library(adephylo)
library(plyr)
library(dplyr)
library(tidyr) 


###Multistate ACR
mussel_tree <- read.tree("Mussels_with_host.tre")
host_infection <- read.csv("Host_infection_strategy_v2.csv", header=T,row.names = 1)
host_info<-setNames(host_infection$Combined_phy_cut, rownames(host_infection))

test_mk <- fitpolyMk(mussel_tree,as.factor(host_info),model = "ER")
trees <- make.simmap(ladderize(mussel_tree),x=test_mk$data,model=test_mk$index.matrix,nsim=100)
acr_result <- summary(trees)
acr_result$ace<- data.frame(acr_result$ace) %>% mutate_all(~as.numeric(as.character(.))) %>%
  select_if(~max(., na.rm = TRUE) >= 0.1)
cols<-setNames(colorRampPalette(c("black","yellow","orange","red","purple", "blue","green", "brown", "grey"))(12),
               colnames(data.frame(acr_result$ace)))


pdffn = "ACR.pdf"
pdf(pdffn, width=8.5, height=11)
plot(acr_result,colors=cols,cex=c(0.4,0.3), ftype="i")
legend(x="topleft",legend=colnames(acr_result$ace),pt.cex=2.4,pch=21,
       pt.bg=cols)
dev.off()  # Turn off PDF
cmdstr = paste("open ", pdffn, sep="")
system(cmdstr) 