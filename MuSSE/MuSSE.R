library(ggplot2)
library(devtools)
library(ggtree)
library(RevGadgets)
library(coda)
library(magrittr)
library(tidyverse)
library(convenience)

#Check convergence
check_Musse <- checkConvergence(list_files=c("output/mussels_BiSSE_run_1.log","output/mussels_BiSSE_run_2.log"), format = "revbayes", 
                                control = makeControl(tracer = T, burnin = 0.1, precision = 0.01))

check_Musse$continuous_parameters$compare_runs
check_Musse$continuous_parameters$ess

# read in and process the ancestral states
musse_file <- paste0("output/mussels_BiSSE.log")
pdata <- processSSE(musse_file, burnin = 0.1)
pdata_net <- pdata %>% filter(rate == "net-diversification")

# plot the rates
plot <- plotMuSSE(pdata_net) +
  theme(legend.position = c(0.75,0.75),
        legend.key.size = unit(0.4, 'cm'), #change legend key size
        legend.title = element_text(size=8), #change legend title font size
        legend.text = element_text(size=8))

ggsave(paste0("MuSSE_div_rates_host_infection.pdf"),plot, width=11, height=8.5)
