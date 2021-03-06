#' @name dlr
#' @title Genotype likelihood ratio distance (Dlr)
#' @description The function computes Paetkau's et al. (1997) genotype likelihood
#' ratio distance (Dlr).
#' @param data The output assignment file (home likelihood or
#' likelihood ratio statistics) from GENODIVE.
#' @param l.skip (integer) The number of lines to skip before the individuals info
#' in GenoDive assignment results (see Vignette).
#' @param number.individuals (integer) The number of individuals analysed.

#' @param number.pop (integer) The number of populations analysed.
#' @param pop.id.start (Optional) The start of your population id
#' in the name of your individual sample. Your individuals are identified 
#' in this form : SPECIES-POPULATION-MATURITY-YEAR-ID = CHI-QUE-ADU-2014-020,
#' then, \code{pop.id.start} = 5. If you didn't name your individuals
#' with the pop id in it, use the \code{strata} argument. 
#' @param pop.id.end (Optional) The end of your population id
#' in the name of your individual sample. Your individuals are identified 
#' in this form : SPECIES-POPULATION-MATURITY-YEAR-ID = CHI-QUE-ADU-2014-020,
#' then, \code{pop.id.end} = 7. If you didn't name your individuals
#' with the pop id in it, use the \code{strata} argument.
#' @param strata (optional) A tab delimited file with 2 columns with header:
#' \code{INDIVIDUALS} and \code{STRATA}. Default: \code{strata = NULL}.
#' The \code{STRATA} column is used here as the populations id of your sample. 

#' @param pop.levels A character string with your sampling sites or populations 
#' in the order you prefer (for tables and figure).
#' @param pop.labels (optional) A character string for your populations labels.
#' If you need to rename sampling sites in \code{pop.levels} or combined sites/pop
#' into a different names, here is the place.

#' @param filename (optional) Name of the file prefix for
#' the matrix and the table written in the working directory. 
#' @return A list with 3 objects of class: table ($dlr.table), dist (a lower
#' diagonal matrix, $dlr.dist), data.frame (a mirrored matrix, $dlr.matrix).
#' @import dplyr
#' @import readr
#' @import lazyeval
#' @import stringi
#' @importFrom  stats as.dist dist
#' @export 
#' @rdname dlr
#' @references Paetkau D, Slade R, Burden M, Estoup A (2004) 
#' Genetic assignment methods for the direct, real-time estimation of 
#' migration rate: a simulation-based exploration of accuracy and power. 
#' Molecular Ecology, 13, 55-65.
#' @references Paetkau D, Waits LP, Clarkson PL, Craighead L, Strobeck C (1997)
#'  An empirical evaluation of genetic distance statistics using microsatellite
#'   data from bear (Ursidae) populations. Genetics, 147, 1943-1957.
#' @references Meirmans PG, Van Tienderen PH (2004) genotype and genodive: 
#' two programs for the analysis of genetic diversity of asexual organisms. 
#' Molecular Ecology Notes, 4, 792-794.
#' @author Thierry Gosselin \email{thierrygosselin@@icloud.com}

# required to pass the R CMD check and have 'no visible binding for global variable'
if (getRversion() >= "2.15.1") {
  utils::globalVariables(
    c('INDIVIDUALS', 'Current', 'Inferred', 'Lik_max', 'Lik_home', 'Lik_ratio', 
      'POP_ID', 'RATIO', 'DLR', 'DLR_RELATIVE')
  )
}

dlr <- function (data, 
                 l.skip, 
                 number.individuals, 
                 number.pop, 
                 pop.id.start, 
                 pop.id.end, 
                 pop.levels, 
                 pop.labels, 
                 strata,
                 filename) {
  
  if (missing(data)) stop("GenoDive file missing")
  if (missing(strata)) strata <- NULL
  if (missing(pop.id.start)) pop.id.start <- NULL
  if (missing(pop.id.end)) pop.id.end <- NULL
  if (is.null(strata) & is.null(pop.id.start) & is.null(pop.id.end)) {
    stop("pop.id.start and pop.id.end or strata arguments are required to 
         identify your populations")
  }
  if (missing(pop.labels)) pop.labels <- pop.levels
  if (missing(filename)) filename <- NULL
  
  
  # import and modify the assignment file form GenoDive-------------------------
  assignment <- read_delim(
    data,
    delim = "\t",
    skip = l.skip,
    n_max = number.individuals,
    col_names = TRUE,
    progress = interactive(),
    col_types = stri_join("cccddd", stri_dup("d", times = number.pop), sep = "")) %>% 
    select(-c(Current, Inferred, Lik_max, Lik_home, Lik_ratio))
  
  if (is.null(strata)){
    header <- names(assignment)
    header.sites <- header[2:(1+number.pop)]
    header.sites.clean <- stri_sub(header.sites, pop.id.start, pop.id.end)
    header.pop <- stri_replace_all_fixed(header.sites.clean, pop.levels, pop.labels, vectorize_all = FALSE)
    new.header <- c("INDIVIDUALS", header.pop)
    colnames(assignment) <- new.header
    
    assignment <- assignment %>%
      mutate(
        POP_ID = stri_sub(INDIVIDUALS, pop.id.start, pop.id.end),
        POP_ID = factor(stri_replace_all_fixed(POP_ID, pop.levels, pop.labels, vectorize_all = FALSE), levels = unique(pop.labels), ordered = TRUE),
        POP_ID = droplevels(POP_ID),
        INDIVIDUALS =  as.character(INDIVIDUALS)
      )
  } else { # strata provided
    strata.df <- read_tsv(file = strata, col_names = TRUE, col_types = "cc") %>% 
      rename(POP_ID = STRATA)
    
    header.pop <- as.character(unique(strata.df$POP_ID))
    new.header <- c("INDIVIDUALS", header.pop)
    colnames(assignment) <- new.header
    
    assignment <- assignment %>%
      mutate(INDIVIDUALS =  as.character(INDIVIDUALS)) %>% 
      left_join(strata.df, by = "INDIVIDUALS") %>% 
      mutate(POP_ID = factor(POP_ID, levels = unique(pop.labels), ordered =TRUE))
  }
  # Dlr relative for one combination of pop-------------------------------------
  dlr.relative <- function(pop1, pop2){
    
    dlr <- suppressWarnings(
      assignment %>%
        filter_(interp(~ POP_ID == as.name(pop1) | POP_ID == as.name(pop2))) %>%
        group_by(INDIVIDUALS) %>%
        mutate_(
          RATIO1 = interp(~pop1 - pop2, pop1 = as.name(pop1), pop2 = as.name(pop2)),
          RATIO2 = interp(~pop2 - pop1, pop1 = as.name(pop1), pop2 = as.name(pop2)),
          RATIO = interp(~ifelse(POP_ID == pop1, c.RATIO1, c.RATIO2),
                         POP_ID = quote(POP_ID), pop1 = as.name("pop1"),
                         c.RATIO1 = quote(RATIO1), c.RATIO2 = quote(RATIO2))) %>% 
        group_by(POP_ID) %>%
        summarise(DLR_RELATIVE = (sum(RATIO)/length(RATIO)^2)) %>%
        ungroup %>%
        summarise(DLR_RELATIVE = sum(DLR_RELATIVE)/2)
    )
    return(dlr)
  }
  
  # All combination of populations----------------------------------------------
  pop.pairwise <- combn(unique(pop.labels), 2)
  pop.pairwise <- matrix(pop.pairwise,nrow = 2)
  
  # Dlr for all pairwise populations--------------------------------------------
  dlr.all.pop <- as.numeric()
  for(i in 1:ncol(pop.pairwise)){
    dlr.all.pop[i] <- dlr.relative(pop1 = pop.pairwise[1,i], 
                                   pop2 = pop.pairwise[2,i])
  }
dlr.all.pop <- as.numeric(dlr.all.pop)

# Table with Dlr--------------------------------------------------------------
names.pairwise <- combn(unique(pop.labels), 2, paste, collapse = '-')

dlr.table <- data_frame(PAIRWISE_POP = names.pairwise, DLR = dlr.all.pop) %>%
  mutate(DLR = round(as.numeric(DLR), 2))


# Dist and Matrix-------------------------------------------------------------
dlr.dist <- stats::dist(1:length(unique(pop.labels)))
dlr.dist.matrix <- dlr.all.pop
attributes(dlr.dist.matrix) <- attributes(dlr.dist)
dlr.dist.matrix <- as.matrix(dlr.dist.matrix)
colnames(dlr.dist.matrix) <- rownames(dlr.dist.matrix) <- unique(pop.labels)
dlr.dist.matrix <- stats::as.dist(dlr.dist.matrix)

dlr.matrix <- as.data.frame(as.matrix(dlr.dist.matrix)) %>%
  add_rownames(var = "POP")

# Results---------------------------------------------------------------------
dlr.results.list <- list()
dlr.results.list$dlr.table <- dlr.table
dlr.results.list$dlr.dist <- dlr.dist.matrix
dlr.results.list$dlr.matrix <- dlr.matrix

# Write file to working directory --------------------------------------------
if (is.null(filename)) {
  message("Writing files to directory: no")
} else {
  # saving table
  filename.table <- stri_join(filename, "table.tsv", sep = ".") 
  write_tsv(dlr.table, filename.table)
  
  # saving matrix
  filename.matrix <- stri_join(filename, "matrix.tsv", sep = ".") 
  write_tsv(dlr.matrix, filename.matrix)
  message("Writing files to directory: yes")
  message(paste0("Filenames : ", "\n", filename.table, "\n", filename.matrix))
}
return(dlr.results.list)  
}

# Dlr absolute
# dlr.absolute <- assignment %>%
#   group_by(Individuals) %>%
#   mutate_(
#     RATIO1 = interp(~pop1 - pop2, pop1 = as.name(pop1), pop2 = as.name(pop2)),
#     RATIO2 = interp(~pop2 - pop1, pop1 = as.name(pop1), pop2 = as.name(pop2)),
#     RATIO = interp(~ifelse(Populations == pop1, c.RATIO1, c.RATIO2), Populations = quote(Populations), pop1 = as.name("pop1"), c.RATIO1 = quote(RATIO1), c.RATIO2 = quote(RATIO2))) %>% 
#     group_by(Populations) %>%
#     summarise(DLR_ABSOLUTE = sum(RATIO)/length(RATIO)) %>%
#     ungroup %>%
#     summarise(DLR_ABSOLUTE = sum(DLR_ABSOLUTE)/2)
