.reg <- new.env(parent = emptyenv())

put <- function(id, value) assign(id, value, envir = .reg)

lookup <- function(id) get0(id, envir = .reg, inherits = FALSE)
