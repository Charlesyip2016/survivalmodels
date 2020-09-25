#' @title Akritas Conditional Non-Parametric Survival Estimator
#' @name akritas
#'
#' @description The Akritas survival estimator is a conditional nearest-neighbours approach to the
#' more common Kaplan-Meier estimator. Common usage includes IPCW Survival models and measures,
#' which do not assume that censoring is independent of the covariates.
#'
#' @details
#' This implementation uses a fit/predict interface to allow estimation on unseen data after
#' fitting on training data. This is achieved by fitting the empirical CDF on the training data
#' and applying this to the new data.
#'
#' @param ... `ANY` \cr
#' Additional arguments, currently unused.
#'
#' @template param_traindata
#'
#' @references
#' Akritas, M. G. (1994).
#' Nearest Neighbor Estimation of a Bivariate Distribution Under Random Censoring.
#' Ann. Statist., 22(3), 1299–1327.
#' \doi{10.1214/aos/1176325630}
#'
#' @return An object inheriting from class `akritas`.
#'
#' @examples
#' if (requireNamespace("distr6", quietly = TRUE) &&
#'     requireNamespace("survival", quietly = TRUE)) {
#'
#'   library(survival)
#'   fit <- akritas(Surv(time, status) ~ ., data = rats[1:10, ])
#'   print(fit)
#'
#'   # alternative function calls
#'   akritas(data = rats[1:10, ], time_variable = "time", status_variable = "status")
#'   akritas(x = rats[1:10, c("litter", "rx", "sex")], y = Surv(rats$time, rats$status))
#' }
#' @export
akritas <- function(formula = NULL, data = NULL, reverse = FALSE,
  time_variable = NULL, status_variable = NULL,
  x = NULL, y = NULL, ...) {

  requireNamespace("distr6")
  requireNamespace("survival")

  call <- match.call()

  data <- clean_train_data(formula, data, time_variable, status_variable, x, y, reverse)

  # use multivariate Empirical if multiple covariates otherwise univariate
  if (ncol(data$x) == 1) {
    Fhat <- distr6::Empirical$new(data$x)
  } else {
    Fhat <- distr6::EmpiricalMV$new(data$x)
  }

  return(structure(list(y = data$y, x = data$x,
                        xnames = colnames(data$x),
                        Fhat = Fhat,
                        FX = Fhat$cdf(data = data$x),
                        call = call),
                   name = "Akritas Estimator",
                   class = c("akritas", "survivalmodel")
  ))
}

#' @title Predict method for Akritas Estimator
#'
#' @description Predicted values from a fitted Akritas estimator.
#'
#' @details
#' This implementation uses a fit/predict interface to allow estimation on unseen data after
#' fitting on training data. This is achieved by fitting the empirical CDF on the training data
#' and applying this to the new data.
#'
#' @param object (`akritas(1)`)\cr
#' Object of class inheriting from `"akritas"`.
#' @param newdata `(data.frame(1))`\cr
#' Testing data of `data.frame` like object, internally is coerced with [stats::model.matrix()].
#' If missing then training data from fitted object is used.
#' @param times `(numeric())`\cr
#' Times at which to evaluate the estimator. If `NULL` (default) then evaluated at all unique times
#' in the training set.
#' @param lambda (`numeric(1)`)\cr
#' Bandwidth parameter for uniform smoothing kernel in nearest neighbours estimation.
#' The default value of `0.5` is arbitrary and should be chosen by the user. If `lambda = 1` then
#' internally [survival::survfit] is called to fit the Kaplan-Meier estimator.
#' @param type (`numeric(1)`)\cr
#' Type of predicted value. Choices are survival probabilities over all time-points in training
#' data (`"survival"`) or a relative risk ranking (`"risk"`), which is the mean cumulative hazard
#' function over all time-points, or both (`"all"`).
#' @param distr6 `(logical(1))`\cr
#' If `FALSE` (default) and `type` is `"survival"` or `"all"` returns data.frame of survival
#' probabilities, otherwise returns a [distr6::VectorDistribution()].
#' @param ... `ANY` \cr
#' Currently ignored.
#'
#' @references
#' Akritas, M. G. (1994).
#' Nearest Neighbor Estimation of a Bivariate Distribution Under Random Censoring.
#' Ann. Statist., 22(3), 1299–1327.
#' \doi{10.1214/aos/1176325630}
#'
#' @return A `numeric` if `type = "risk"`, a [distr6::VectorDistribution()] (if `distr6 = TRUE`)
#' and `type = "survival"`; a `data.frame` if (`distr6 = FALSE`) and `type = "survival"` where
#' entries are survival probabilities with rows of observations and columns are time-points;
#' or a list combining above if `type = "all"`.
#'
#'
#' @examples
#' if (requireNamespace("distr6", quietly = TRUE) &&
#'     requireNamespace("survival", quietly = TRUE)) {
#' library(survival)
#' train <- 1:10
#' test <- 11:20
#' fit <- akritas(Surv(time, status) ~ ., data = rats[train, ])
#' predict(fit, newdata = rats[test, ])
#'
#' # when lambda = 1, identical to Kaplan-Meier
#' fit <- akritas(Surv(time, status) ~ ., data = rats[1:100, ])
#' predict_akritas <- predict(fit, newdata = rats[1:100, ], lambda = 1)[1, ]
#' predict_km <- survfit(Surv(time, status) ~ 1, data = rats[1:100, ])$surv
#' all(predict_akritas == predict_km)
#'
#' # Use distr6 = TRUE to return a distribution
#' predict_distr <- predict(fit, newdata = rats[test, ], distr6 = TRUE)
#' predict_distr$survival(100)
#'
#' # Return a relative risk ranking with type = "risk"
#' predict(fit, newdata = rats[test, ], type = "risk")
#'
#' # Or survival probabilities and a rank
#' predict(fit, newdata = rats[test, ], type = "all", distr6 = TRUE)
#' }
#' @export
predict.akritas <- function(object, newdata, times = NULL,
  lambda = 0.5,
  type = c("survival", "risk", "all"),
  distr6 = FALSE, ...) {

  type <- match.arg(type)
  unique_times <- sort(unique(object$y[, 1, drop = FALSE]))
  if (is.null(times)) {
    times <- unique_times
  } else {
    times <- sort(unique(times))
  }

  truth <- object$y
  newdata <- clean_test_data(object, newdata)

  ord <- order(truth[, 1], decreasing = TRUE)
  truth <- truth[ord, ]
  fx_train <- object$FX[ord]

  if (lambda == 1) {
    surv <- survival::survfit(survival::Surv(time, status) ~ 1, data.frame(object$y))$surv
    surv <- matrix(surv, nrow(newdata), length(surv),
      byrow = TRUE,
      dimnames = list(NULL, round(unique_times)))

    find <- findInterval(times, as.numeric(colnames(surv)))
    find[find == 0] <- 1
    surv <- surv[, find, drop = FALSE]
    colnames(surv) <- times
  } else {
    surv <- C_Akritas(
      truth = truth,
      times = times,
      unique_times = unique_times,
      FX_train = fx_train,
      FX_predict = object$Fhat$cdf(data = newdata),
      lambda = lambda
    )
    colnames(surv) <- round(times, 2)
  }

  ret <- list()

  if (type %in% c("survival", "all")) {
    if (!distr6) {
      ret$surv <- surv
    } else {
      cdf <- apply(surv, 1, function(x) list(cdf = 1 - x))
      ret$surv <- distr6::VectorDistribution$new(
        distribution = "WeightedDiscrete",
        shared_params = list(x = unique_times),
        params = cdf,
        decorators = c(
          "CoreStatistics",
          "ExoticStatistics"
        )
      )
    }
  }

  if (type %in% c("risk", "all")) {
    ret$risk <- rowMeans(-log(surv))
  }

  if (length(ret) == 1) {
    return(ret[[1]])
  } else {
    return(ret)
  }
}