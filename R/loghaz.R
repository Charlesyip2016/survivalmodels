#' @description Logistic-Hazard fits a discrete neural network based on a cross-entropy loss
#' and predictions of a discrete hazard function, also known as Nnet-Survival.
#'
#' @template pycox
#' @templateVar call LogisticHazard
#' @templateVar name Logistic-Hazard
#' @templateVar fun loghaz
#'
#' @template param_customnet
#' @template param_discretise
#' @template param_traindata
#' @template return_train
#'
#' @references
#' Gensheimer, M. F., & Narasimhan, B. (2018).
#' A Simple Discrete-Time Survival Model for Neural Networks, 1–17.
#' https://doi.org/arXiv:1805.00917v3
#'
#' Kvamme, H., & Borgan, Ø. (2019).
#' Continuous and discrete-time survival prediction with neural networks.
#' https://doi.org/arXiv:1910.06724.
#'
#'
#' @examples
#' \donttest{
#' if (requireNamespaces("reticulate")) {
#'   # all defaults
#'   loghaz(data = simsurvdata(50))
#'
#'   # common parameters
#'   loghaz(data = simsurvdata(50), frac = 0.3, activation = "relu",
#'     num_nodes = c(4L, 8L, 4L, 2L), dropout = 0.1, early_stopping = TRUE, epochs = 100L,
#'     batch_size = 32L)
#' }
#' }
#'
#' @export
loghaz <- function(formula = NULL, data = NULL, reverse = FALSE,
                    time_variable = "time", status_variable = "status",
                    x = NULL, y = NULL, frac = 0, cuts = 10, cutpoints = NULL,
                    scheme = c("equidistant", "quantiles"), cut_min = 0,
                    activation = "relu", custom_net = NULL,
                    num_nodes = c(32L, 32L), batch_norm = TRUE,
                    dropout = NULL, device = NULL, early_stopping = FALSE,
                    best_weights = FALSE,  min_delta = 0, patience = 10L, batch_size = 256L,
                    epochs = 1L, verbose = FALSE, num_workers = 0L, shuffle = TRUE, ...) {

  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Package 'reticulate' required but not installed.") # nocov
  }

  call <- match.call()

  data <- .pycox_prep(formula, data, time_variable, status_variable, x, y, reverse, activation,
                      frac = frac, discretise = TRUE, model = "loghaz", cuts = cuts,
                      cutpoints = cutpoints, scheme = match.arg(scheme), cut_min = cut_min)

  pycox <- reticulate::import("pycox")
  torchtuples <- reticulate::import("torchtuples")

  if (!is.null(custom_net)) {
    net <- custom_net
  } else {
    net <- torchtuples$practical$MLPVanilla(
      in_features = data$x_train$shape[1],
      num_nodes = reticulate::r_to_py(as.integer(num_nodes)),
      activation = data$activation,
      out_features = data$labtrans$out_features,
      batch_norm = batch_norm,
      dropout = dropout
    )
  }

  # Get optimizer and set-up model
  model <- pycox$models$LogisticHazard(
    net = net,
    duration_index = data$labtrans$cuts,
    optimizer = get_pycox_optim(net = net, ...),
    device = device
  )

  model$fit(
    input = data$x_train,
    target = data$y_train,
    callbacks = get_pycox_callbacks(early_stopping, best_weights, min_delta, patience),
    val_data = data$val,
    batch_size = as.integer(batch_size),
    epochs = as.integer(epochs),
    verbose = verbose,
    num_workers = as.integer(num_workers),
    shuffle = shuffle
  )

  structure(list(y = data$y, x = data$x,
                 xnames = colnames(data$x),
                 model = model,
                 call = call),
            name = "Logistic-Hazard Neural Network",
            class = c("loghaz", "pycox", "survivalmodel")
  )
}
