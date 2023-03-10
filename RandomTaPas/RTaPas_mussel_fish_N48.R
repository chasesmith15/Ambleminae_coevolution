#############################################################################
# Script to implement — Random Tanglegram Partitions (Random TaPas):          #
# An Alexandrian approach to the cophylogenetic Gordian knot                  #
# J.A. Balbuena, O.A. Pérez-Escobar, C. Llopis-Belenguer, I. Blasco-Costa     #
# Submitted                                                                   #
# For questions/feedback contact j.a.balbuena@uv.es                           #
# LICENSE: MIT (https://opensource.org/licenses/MIT)                          #
# YEAR: 2019                                                                  #
# COPYRIGHT HOLDER: Symbiosis Ecol. & EVol. Lab @ U. Valencia                 #
#############################################################################
# Demonstration with data of orchids and their euglossine bee pollinators from#
# Ramírez et al. (2011 Science 333: 1742-1746)                                #
# The original terminal names of the euglossine bee pollinators tree have been# 
# shortened to facilitate graphical visualization of results. See table in    #
# See BeeTree_Abbr_terminal_names.txt.                                        #
#############################################################################
#                  Documentation and scripts available at                     #
#                https://github.com/Ligophorus/RandomTaPas/                   #
#############################################################################
# Load libraries 
library(magrittr)
library(phylotools)
library(paco)
library(phytools)
library(distory)
library(GiniWegNeg)
library(parallel)

# Set number of runs (N) for Random TaPas
N= 1e+4
# Functions (6):
# foo 1 of 6
trimHS.maxC <- function (N, HS, n, check.unique= FALSE) {
  # For N runs, chooses n unique one-to-one associations and trims
  # the h-s association matrix to include the n associations only.
  #
  # Args:
  #   N:  Number of runs.
  #   HS: Host-symbiont association matrix.
  #   n:  Number of unique associations
  #   check.unique: if TRUE discards duplicated trimmed matrices.
  # Returns:
  #   A list of trimmed matrices.
  trim.int <- function (x, HS, n) {
    HS.LUT <- which(HS == 1, arr.in= TRUE)
    HS.LUT <- cbind(HS.LUT, 1:nrow(HS.LUT))
    df <- as.data.frame(HS.LUT)
    hs.lut <- subset(df[sample(nrow(df)), ],
                     !duplicated(row) & !duplicated(col))
    if (nrow(hs.lut) < n) hs <- NULL else {
      hs.lut <- hs.lut[sample(nrow(hs.lut), n), ]
      hs <- diag(nrow(hs.lut))
      rownames(hs) <- rownames(HS[hs.lut[ ,1], ])
      colnames(hs) <- colnames(HS[ ,hs.lut[ ,2]])
      return(hs)
    }
  }
  trim.HS <- lapply(1:N, trim.int, HS= HS, n= n )
  if (check.unique == TRUE) trim.HS <- unique(trim.HS)
  if (length(trim.HS) < N)
    warning("No. of trimmed H-S assoc. matrices < No. of runs")
  return(trim.HS)
}
# foo 2 of 6.
geo.D <- function (hs, treeH, treeS) {
  # For any trimmed matrix produced with trimHS.maxC, it prunes the host &
  # symbiont phylogenies to conform with the trimmed matrix and computes the
  # geodesic distance between the pruned trees
  # NOTE: This function can only be used with strictly bifurcating trees.
  #
  # Args.:
  #   hs: trimmed matrix
  #   treeH: host phylogeny
  #   treeS: symbiont phylogeny
  # Returns:
  #   A geodesic distance
  treeh <- ape::drop.tip(treeH, setdiff(treeH$tip.label, rownames(hs)))
  trees <- ape::drop.tip(treeS, setdiff(treeS$tip.label, colnames(hs)))
  # foo distory requires same labels in both trees. Dummy labels are produced.
  # 1st reorder hs as per tree labels:
  hs <- hs[treeh$tip.label, trees$tip.label]
  # 2nd swap trees labels with corresponding ones in treeh:
  hs.lut <- which(hs[treeh$tip.label, trees$tip.label]==1, arr.ind = TRUE)
  dummy.labels <- rownames(hs.lut)
  trees$tip.label <- dummy.labels
  combo.tree <- list(treeh, trees)
  gd <- distory::dist.multiPhylo(combo.tree)
  return(gd)
}
# foo 3 of 6
paco.ss <- function (hs, treeH, treeS, symmetric= FALSE,
                     proc.warns= FALSE, ei.correct= "none") {
  # For any trimmed matrix produced with trimHS.maxC, it prunes the host &
  # symbiont phylogenies to conform with the trimmed matrix and runs
  # Procrustes Approach to Cophylogeny (PACO) to produce the squared sum of
  # residuals of the Procrustes superimosition of the host and symbiont
  # configurations in Euclidean space.
  #
  # Args.:
  #   hs: trimmed matrix
  #   treeH: host phylogeny
  #   treeS: symbiont phylogeny
  #   symmetric: specifies the type of Procrustes superimposition
  #   proc.warns: switches on/off trivial warnings returned when treeH and
  #               treeS differ in size
  #   ei.correct: specifies how to correct potential negative eigenvalues
  # Returns:
  #   A sum of squared residuals
  eigen.choice <- c("none", "lingoes", "cailliez", "sqrt.D")
  if (ei.correct %in% eigen.choice == FALSE)
    stop(writeLines("Invalid eigenvalue correction parameter.\r
               Correct choices are 'none', 'lingoes', 'cailliez' or 'sqrt.D'"))
  treeh <- ape::drop.tip(treeH, setdiff(treeH$tip.label, rownames(hs)))
  trees <- ape::drop.tip(treeS, setdiff(treeS$tip.label, colnames(hs)))
  # Reorder hs as per tree labels:
  hs <- hs[treeh$tip.label, trees$tip.label]
  DH <- cophenetic(treeh)
  DP <- cophenetic(trees)
  if (ei.correct == "sqrt.D"){DH<- sqrt(DH); DP<- sqrt(DP); ei.correct="none"}
  D <- paco::prepare_paco_data(DH, DP, hs)
  D <- paco::add_pcoord(D, correction= ei.correct)
  if (proc.warns == FALSE) D <- vegan::procrustes(D$H_PCo, D$P_PCo,
                                                  symmetric = symmetric) else
                                                    D <- suppressWarnings(vegan::procrustes(D$H_PCo, D$P_PCo,
                                                                                            symmetric = symmetric))
  return(D$ss)
}
# foo 4 of 6
link.freq <- function (x, fx, HS, percentile= 0.01,
                       sep= "-", below.p= TRUE, res.fq= TRUE) {
  # Determines the frequency of each host-symbiont association occurring in a
  # given percentile of cases that maximize phylogenetic congruence. 
  #
  # Args.:
  #   x: list of trimmed matrices produced by trimHS.maxC
  #   fx: vector of statistics produced with either geo.D or paco.ss
  #   percentile: percentile to evaluate
  #   sep: character that separates host and symbiont labels
  #   below.p: determines whether frequencies are to be computed below or above
  #            the percentile set
  #   res.fq: determines whether a correction to avoid one-to-one associations
  #           being overrepresented in the percentile evaluated
  # Returns:
  #   Data frame with labels of hosts, symbionts and host-symbiont associations
  #   in three columns. Column 4 displays the frequency of occurrence of each
  #   host-symbiont association in p. If res.fq= TRUE, Column 5 displays the
  #   corrected frequencies as a residual = Observed - Expected frequency
  
  if (below.p ==TRUE) 
    percent <- which(fx <= quantile(fx, percentile, na.rm=TRUE)) else
      percent <- which(fx >= quantile(fx, percentile, na.rm=TRUE))
    trim.HS <- x[percent]
    paste.link.names <- function(X, sep) {
      X.bin <- which(X>0, arr.in=TRUE)
      Y <- diag(nrow(X.bin))
      Y <- diag(nrow(X.bin))
      rownames(Y) <- rownames(X)[X.bin[,1]]
      colnames(Y) <- colnames(X)[X.bin[,2]]
      pln <- paste(rownames(Y), colnames(Y), sep=sep) 
      return(pln)
    }
    link.names <- t(sapply(trim.HS, paste.link.names, sep=sep))
    lf <- as.data.frame(table(link.names))
    HS.LUT <- which(HS ==1, arr.in=TRUE) 
    linkf <- as.data.frame(cbind(rownames(HS)[HS.LUT[,1]],
                                 colnames(HS)[HS.LUT[,2]]))
    colnames(linkf) <- c('H', 'S')
    linkf$HS <- paste(linkf[,1], linkf[,2], sep=sep)
    linkf$Freq <- rep(0, nrow(linkf))
    linkf[match(lf[,1],linkf[,3]), 4] <- lf[,2]
    linkf2 <- linkf
    #
    if (res.fq == TRUE) { 
      link.names.all <- t(sapply(x, paste.link.names, sep=sep))
      lf.all <- as.data.frame(table(link.names.all))
      linkf.all <- as.data.frame(cbind(rownames(HS)[HS.LUT[,1]],
                                       colnames(HS)[HS.LUT[,2]]))
      colnames(linkf.all) <- c('H', 'S')
      linkf.all$HS <- paste(linkf.all[,1], linkf.all[,2], sep=sep)
      linkf.all$Freq <- rep(0, nrow(linkf.all))
      linkf.all[match(lf.all[,1], linkf.all[,3]), 4] <- lf.all[,2]
      w <- linkf.all[,4]
      w <- as.matrix(w*percentile)
      wFq <- linkf$Freq - w
      linkf$wFq <- wFq
    } else linkf <- linkf2
    return(linkf)
}
# foo 5 of 6
One2one.f <- function (hs, reps= 1e+4) {
  # For a matrix of host-symbiont associations, it finds the maximum n for
  #  which one-to-one unique associations can be picked in trimHS.maxC over
  #  a number of runs.
  #
  # Args.:
  #   hs: matrix of host-symbiont associations
  #   reps: number of runs to evaluate
  # Returns:
  #   maximum n
  HS.LUT <- which(hs ==1, arr.in=TRUE)
  HS.LUT <- cbind(HS.LUT,1:nrow(HS.LUT))
  df <- as.data.frame(HS.LUT)
  V <- rep(NA,reps)
  for(i in 1:reps){
    hs.lut <- subset(df[sample(nrow(df)),],
                     !duplicated(row) & !duplicated(col))
    n <- sum(HS)
    while (n >0) {
      n <- n-1;
      if (nrow(hs.lut) == n) break
    }
    V[i]<- n
  }
  V <- min(V)
  return(V)
}
# foo 6 of 6
tangle.gram <- function(treeH, treeS, hs, colscale= "diverging", colgrad,
                        nbreaks=50, fqtab, res.fq= TRUE, node.tag=TRUE, 
                        cexpt=1, ...) {
  # Wrapper of cophylo.plot of package phytools is used for mapping as heatmap
  # the host-symbiont frequencies estimated by Random TaPas on a tanglegram. It
  # also plots the average frequency of occurrence of each terminal and
  # optionally, the fast maximum likelihood estimators of ancestral states of
  # each node.
  #
  # Args.:
  #   treeH: host phylogeny
  #   treeS: symbiont phylogeny
  #   hs: host-symbiont association matrix
  #   colscale: either "diverging" (color reflects distance from 0)
  #             or "sequential" (color reflects distance from min value)
  #   colgrad: if colscale = vector defining the color gradient of the heatmap
  #   nbreaks: number of discrete values along colorgrad
  #   fqtab: dataframe produced with link.freq
  #   res.fq: if TRUE it processes corrected frequencies of fqtab (colum 5);
  #   if FALSE uncorrected frequencies (colum 4) are be processed
  #   node.taq: specifies whether maximum likelihood estimators of ancestral
  #             states are to be computed 
  #   cexpt: size of color points at terminals and nodes
  #   ...: any graphical option admissible in cophylo.plot  
  # Returns:
  #   A tanglegram with quantitative information displayed as heatmap.	
  ## cophyloplot
  colscale.choice <- c("diverging", "sequential")
  if (colscale %in% colscale.choice == FALSE)
    stop(writeLines("Invalid colscale parameter.\r
                    Correct choices are 'diverging', 'sequential'"))
  colscale.range <- function(x) {
    rescale.range <- function(x) {
      xsq <- round(x)
      if(colscale=="sequential") {
        y <- range(xsq)
        col_lim <- (y[1]:y[2])-y[1]+1
        xsq <- xsq-y[1]+1
        new.range <- list(col_lim, xsq)
      } else {
        x1 <- x[which(x<0)]
        if(length(x1) < 2) stop("Not enough negative values for diverging scale.
                                 Choose colscale= 'sequential' instead")
        x2 <- x[which(x >= 0)]
        x1 <- round(x1)
        x2 <- round(x2)
        y <- max(abs(x))
        col_lim <- (-y:y) + y + 1
        y1 <- range(x1)
        y2 <- range(x2)
        x1 <- x1-y1[1]+1
        x2 <- x2-y2[1]+1
        new.range <- list(col_lim, x1, x2) 
      }
      return(new.range)
    }
    if(colscale=="sequential") {
      NR <- rescale.range(x)
      rbPal <- colorRampPalette(colgrad) 
      linkcolor <- rbPal(nbreaks)[as.numeric(cut(NR[[1]], breaks = nbreaks))]
      NR <- NR[[2]]
      linkcolor <- linkcolor[NR]
    } else {
      NR <- rescale.range(x)
      NR.neg <- NR[[1]] [which (NR[[1]] <= max(NR[[2]]))]
      NR.pos <- NR[[1]] [-NR.neg] - max(NR[[2]])
      m <- median(1:length(colgrad))
      colgrad.neg <- colgrad[which(1:length(colgrad) <= m)]
      colgrad.pos <- colgrad[which(1:length(colgrad) >= m)]
      rbPal <- colorRampPalette(colgrad.neg)
      linkcolor1 <- rbPal(nbreaks)[as.numeric(cut(NR.neg, breaks = nbreaks))]
      rbPal <- colorRampPalette(colgrad.pos)
      linkcolor2 <- rbPal(nbreaks)[as.numeric(cut(NR.pos, breaks = nbreaks))]
      linkcolor1 <- linkcolor1[NR[[2]]]
      linkcolor2 <- linkcolor2[NR[[3]]]
      linkcolor <- rep(NA, length(x))
      linkcolor[which(x< 0)] <- linkcolor1
      linkcolor[which(x>=0)] <- linkcolor2
    }
    return(linkcolor)    
  }
  FQ <- ifelse(res.fq==FALSE, 4 ,5) # determines freq column to evaluate
  if (res.fq ==FALSE & colscale== "diverging") {colscale = "sequential"
  warning("Colscale 'diverging' does not take effect when res.fq = FALSE.
             The color scale shown is sequential")
  }
  LKcolor <- colscale.range(fqtab[,FQ])
  HS.lut <- which(hs ==1, arr.ind=TRUE)
  linkhs <- cbind(rownames(hs)[HS.lut[,1]], colnames(hs)[HS.lut[,2]])
  obj <- phytools::cophylo(treeH,treeS, linkhs)
  phytools::plot.cophylo(obj, link.col=LKcolor, ...)
  
  Hfreq <- aggregate(fqtab[,FQ], by=list(freq = fqtab[,1]), FUN=mean)
  Sfreq <- aggregate(fqtab[,FQ], by=list(freq = fqtab[,2]), FUN=mean)
  
  Hfreq <- Hfreq[match(obj$trees[[1]]$tip.label, Hfreq$freq),]
  Sfreq <- Sfreq[match(obj$trees[[2]]$tip.label, Sfreq$freq),]
  
  if (node.tag==TRUE){
    fit.H <- phytools::fastAnc(obj$trees[[1]],Hfreq[,2])
    fit.S <- phytools::fastAnc(obj$trees[[2]],Sfreq[,2])
    NLH <- colscale.range (fit.H)
    NLS <- colscale.range (fit.S)
    phytools::nodelabels.cophylo(pch=16, col=NLH, cex=cexpt)
    phytools::nodelabels.cophylo(pch=16, col=NLS, cex=cexpt, which="right")
  }
  TLH <- colscale.range (Hfreq[,2])
  TLS <- colscale.range (Sfreq[,2])
  phytools::tiplabels.cophylo(pch=16, col=TLH, cex=cexpt)
  phytools::tiplabels.cophylo(pch=16, col=TLS, cex=cexpt, which="right")
}
############ end of function declaration ######################################
# Read data (It is assumed that input files are in the working directory
# of the R session)
TreeH <- read.newick("host_tree.new") #consensus tree, fish
HS <- as.matrix(read.csv("host_species_matrix_Amb_v3_paco.csv", header = T, row.names = 1)) #interaction matrix

#If needed, Prepare Mussel Tree
#new_names <- read.csv("new_names.csv", header = T)
#mussel_tree <- read.nexus("Amb_PF.tre")
#mussel_tree_renamed <- sub.taxa.label(mussel_tree,new_names)
#mussel_tree_renamed_host <- keep.tip(mussel_tree_renamed, row.names(t(HS)))    #consensus tree, mussels
#write.tree(mussel_tree_renamed_host, "Mussels_with_host.tre")

TreeS <- read.tree("Mussels_with_host.tre")

##If needed, prune fish trees
#fish_trees <- read.tree("actinopt_full.trees") #Read in dated fish tree
#keeps <- c(TreeH$tip.label)

#keep.tip.multiPhylo<-function(phy, tip, ...){
#  if(!inherits(phy,"multiPhylo"))
#    stop("phy is not an object of class \"multiPhylo\".")
#  else {
#    trees<-lapply(phy,keep.tip,tip=tip,...)
#    class(trees)<-"multiPhylo"
#  }
#  trees
#}

#fish_trees_pruned <- keep.tip.multiPhylo(fish_trees, keeps) #100 post. prob. Bayesian trees, fish
#rm(fish_trees)
#write.tree(fish_trees_pruned, "host_100_trees.trees")

fish_trees_pruned <- read.tree("host_100_trees.trees")

##If needed, randomly select, rename, and prune mussel trees
#mussel_trees <- read.nexus("tree.trees") #Read in mussel trees from BEAST
#mussel_trees_10burned <- mussel_trees[7501:48133] #Remove burnin (10%)
#mussel_trees_100 <- sample(mussel_trees_10burned, size=100) #Randomly select 100 trees
#rm(mussel_trees)
#rm(mussel_trees_10burned)

#rename.multiPhylo<-function(phy, dat, ...){
#  if(!inherits(phy,"multiPhylo"))
#    stop("phy is not an object of class \"multiPhylo\".")
#  else {
#    trees<-lapply(phy,sub.taxa.label,dat=dat,...)
#    class(trees)<-"multiPhylo"
#  }
#  trees
#}

#Rename the tips to genus species
#mussel_tree_renamed <- rename.multiPhylo(mussel_trees_100, new_names)
#rm(mussel_trees_100)

#Drop to host data
#with_host <- row.names(t(HS))
#mussel_trees_pruned <- keep.tip.multiPhylo(mussel_tree_renamed,c(with_host)) 
#rm(mussel_tree_renamed)
#write.tree(mussel_trees_pruned, "mussel_100_trees.trees")

mussel_trees_pruned <- read.tree("mussel_100_trees.trees")

# Run Random TaPas with consensus trees #######################################
n= 48 # ~20% of total nº H-S associations
THS <- trimHS.maxC(N, HS, n=n, check.unique=TRUE)
THS[sapply(THS, is.null)] <- NULL
GD <- sapply(THS, geo.D, treeH=TreeH, treeS= TreeS)
PACO <- sapply(THS, paco.ss, treeH=TreeH, treeS= TreeS, 
               symmetric=FALSE, ei.correct="none")
# Extract frequency distributions 
LFGD01 <- link.freq(THS, GD, HS, percentile=0.01, res.fq=TRUE) 
LFPACO01 <- link.freq(THS, PACO, HS, percentile=0.01, res.fq=TRUE)
# Run Random TaPas, 2x1000 posterior prob. trees #############################
GD01 <- matrix(NA, length(fish_trees_pruned), nrow(LFGD01))
PACO01 <- matrix(NA, length(fish_trees_pruned), nrow(LFPACO01))
#
cores <- detectCores()
cl <- makeCluster(cores) # Use all CPUs available
#
pb <- txtProgressBar(min = 0, max = length(fish_trees_pruned), style = 3)
for(i in 1:length(fish_trees_pruned))
{
  GD.CI<-parallel::parSapply(cl, THS, geo.D, treeH=fish_trees_pruned[[i]],
                             treeS= mussel_trees_pruned[[i]])
  LFGD01.CI <- link.freq(THS, GD.CI, HS, percentile=0.01, res.fq=TRUE) 
  GD01[i,] <- LFGD01.CI[,5]
  setTxtProgressBar(pb, i)
}
close(pb)
#
pb <- txtProgressBar(min = 0, max = length(fish_trees_pruned), style = 3)
for(i in 1:length(fish_trees_pruned))
{
  PA.CI<-parallel::parSapply(cl, THS, paco.ss, treeH=fish_trees_pruned[[i]],
                             treeS= mussel_trees_pruned[[i]], symmetric=FALSE, ei.correct="none")
  LFPA01.CI <- link.freq(THS, PA.CI, HS, percentile=0.01, res.fq=TRUE) 
  PACO01[i,] <- LFPA01.CI[,5]
  setTxtProgressBar(pb, i)
}
close(pb)
stopCluster(cl)
# 
colnames(GD01) <- LFGD01[,3]
colnames(PACO01) <- LFPACO01[,3]
#compute CIs and averages of freqs GD
GD.LO <- apply(GD01, 2, quantile, 0.025)
GD.HI <- apply(GD01, 2, quantile, 0.975)
GD.AV <- apply(GD01, 2, mean)
#compute CIs and averages of freqs PACo
PACO.LO <- apply(PACO01, 2, quantile, 0.025)
PACO.HI <- apply(PACO01, 2, quantile, 0.975)
PACO.AV <- apply(PACO01, 2, mean)
# End Random TaPas, 2x1000 post. prob. trees #################################
#
# Plot results ###############################################################
# Barplot of frequencies per host-symbiont association
op <- par(mfrow=c(2,1),mgp = c(2.2, 0.3, 0), mar=c(0,3.2,0.2,0), tck=0.01,
          oma = c(4, 0, 0, 0), xpd=NA)
link.fq <-barplot(GD.AV, horiz=FALSE, xaxt='n', las=2,
                  ylab="Observed − Expected frequency", ylim=c(min(GD.LO),
                                                               max(GD.HI)), col="lightblue")
suppressWarnings(arrows(link.fq, GD.HI, link.fq, GD.LO, length= 0, angle=90, 
                        code=3, col="darkblue",lwd=0.5))
#
link.fq <-barplot(PACO.AV, horiz=FALSE, xaxt='n', las =2,
                  ylab="Observed - Expected frequency", ylim=c(min(PACO.LO),
                                                               max(PACO.HI)), col="lightblue")
suppressWarnings(arrows(link.fq, PACO.HI, link.fq, PACO.LO, length= 0,
                        angle=90, code=3, col="darkblue",lwd=0.5))
#
axis(side=1, at=link.fq[1:length(PACO.AV)], labels=LFPACO01$HS, las=2, 
     tick = FALSE, line= 0.1, cex.axis=0.1)
par(op)
#
# Plot Gini values
GiniGD <- unlist(Gini_RSV(LFGD01[,5]))
GiniPA <- unlist(Gini_RSV(LFPACO01[,5]))
GiniMGD <- unlist(apply(GD01, 1, Gini_RSV))
GiniMPA <- unlist(apply(PACO01, 1, Gini_RSV))
#
boxplot(GiniMGD, GiniMPA, names = c("GD", "PACo"), ylab="Normalized Gini coefficient",
        col="lightblue", las=3)
text(1,GiniGD,"*",cex=2, col="darkblue")
text(2,GiniPA,"*",cex=2, col="darkblue")
#
dev.off()
# Heatmaps on tanglegram 
# Set color scale - this one is supposed to be color-blind friendly
col.scale <- c("darkred","gray90", "darkblue")
# GD results:
tangle.gram(TreeH, TreeS, HS, colscale= "diverging", colgrad=col.scale, 
            nbreaks=50, LFGD01, res.fq=TRUE, link.lwd=1, link.lty=1, fsize=0.5,
            pts=FALSE, link.type="curved", node.tag=TRUE,
            cexpt=1.2, ftype="off")

# PACo results:
tangle.gram(TreeH, TreeS, HS, colscale= "diverging", colgrad= col.scale,
            nbreaks=50, LFPACO01, res.fq=TRUE, 
            link.lwd=1, link.lty=1, fsize=0.5, pts=FALSE, link.type="curved",
            node.tag=TRUE, cexpt=1.2, ftype="off")

############################ END OF SCRIPT ###################################