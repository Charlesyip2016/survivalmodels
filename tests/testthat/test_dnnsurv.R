test_that("silent", {
  expect_silent({fit <- dnnsurv(Surv(time, status) ~ ., data = rats[1:50, ], verbose = FALSE)})
  expect_silent({predict(fit, newdata = rats[51:100, ])})
})