# load required libraries
library(caret)
library(dplyr)
library(ggplot2)
library(rpart)
library(randomForest)

# load data
conversion_data <- read.csv("data/conversion_data.csv")

# inspect the first few rows of data
head(conversion_data)

# summary
summary(conversion_data)
# max age is 123! 

#investigate records wih age greater than 80 years
conversion_data[conversion_data$age > 80,]
# two rows - one from Germany and other from UK. These might be outliers and can be removed.
# Age seems to be a manually entered field. In real life though, we would like to understand 
# how this data was collected. For now, we will remove these records.

conversion_data <- conversion_data[conversion_data$age <= 80,]

# conversion_rate
table(factor(conversion_data$converted))

# plot distribution of total pages
ggplot(data = conversion_data, aes(x = total_pages_visited)) +
        geom_histogram(binwidth = 1, fill = "steelblue", colour = "black")

# distribution of pages is right skewed with most of the visitors visiting 2 or 3 pages.

page_view_conversion <- conversion_data %>% 
                          group_by(total_pages_visited) %>%
                          summarise(conversion_rate =  mean(converted))

ggplot(data = page_view_conversion, aes(x = total_pages_visited, y = conversion_rate)) +
  geom_line()

# nothing surprising. More page view leads to more conversion. Since, you want to buy,
# you have to visit many pages for selecting the item.

# plot the conversion for each country
ggplot(data = conversion_data, aes(x = factor(converted))) + 
        geom_bar() + facet_wrap(~country)

# smallest userbase in Germany. Largest in US. 

# check per country conversion rate
prop.table(table(conversion_data$country, conversion_data$converted), 1)
# highest conversion rate across Germany and lowest across China

# plot distribution of age
ggplot(data = conversion_data, aes(x = age)) + 
        geom_histogram(binwidth = 1, fill = "steelblue", colour = "black")
# number of visitors mostly of age around 30 years.

# plot distribution of age by country
ggplot(data = conversion_data, aes(x = age)) + 
        geom_histogram(binwidth = 1, fill = "steelblue", colour = "black") +
        facet_wrap(~country)
# all countries have similar age distribution of visitors

# plot traffic by channel
ggplot(data = conversion_data, aes(x = source)) + geom_bar(fill = "steelblue")
#highest number from seo

# plot conversion by channel
ggplot(data = conversion_data, aes(x = factor(converted))) +
        geom_bar(fill = "steelblue") +
        facet_wrap(~source)

#tabulate conversion by channel
prop.table(table(conversion_data$source, conversion_data$converted), 1)
# most conversion from ads and SEO although the differences are pretty small.

# what proportion of new users convert
temp <- conversion_data
temp$new_user <- as.factor(temp$new_user)
ggplot(data = temp, aes(x = factor(converted))) + 
        geom_bar(fill = "steelblue") +
        facet_wrap(~new_user)
prop.table(table(temp$new_user, temp$converted), 1)
# older users likely to convert much more than new customers. 7.2% of existing
# users convert and only 1.4% of new users convert.

# correlation matrix for total pages visited and conversion
cor(conversion_data[, c('total_pages_visited', 'converted')])

# train a basic decision tree. Reason for choosing decision tree:
# a. Most of the features are categorical in nature. Ideally suited for Decision tree.
# b. decision tree is more interpreatable and hence might provide insights into which features are important

# split the data into train and test
set.seed(42)
trainIDX <- createDataPartition(conversion_data$converted, 
                                p = 0.75,
                                list = FALSE)
conversion_data$converted <- as.factor(ifelse(conversion_data$converted == 1, "Yes", "No"))
trainX <- conversion_data[trainIDX, -length(conversion_data)]
trainY <- conversion_data$converted[trainIDX]
testX <- conversion_data[-trainIDX, -length(conversion_data)]
testY <- conversion_data$converted[-trainIDX]

# check proportion of conversion rate in train, test and original data
# all must be similar
prop.table(table(conversion_data$converted))
prop.table(table(trainY))
prop.table(table(testY))
# all have around 3.2% conversion rate

tree <- rpart(trainY ~ ., 
               data = cbind(trainX, trainY),
               control = rpart.control(maxdepth = 5))
tree
# seems like total_pages_visited, new_user and country are the most important variables.
# check variable importance from the model
tree_var_imp <- as.data.frame(varImp(tree)) %>% tibble::rownames_to_column()

# plot variable importance
ggplot(data = tree_var_imp, aes(x = rowname, y = Overall)) + 
  geom_bar(stat = "identity", fill = "steelblue", colour = "black")

prediction_tree <- predict(tree, testX, type = "class")
confusionMatrix(prediction_tree, reference = testY, positive = 'Yes')
# Sensitivity of the model is very low (only 65%).

# train a random Forest Model
rf <- randomForest(x = trainX,
                   y = trainY,
                   ntree = 100,
                   keep.forest = TRUE
                   )
rf_prediction = predict(rf, testX, type = "class")
confusionMatrix(rf_prediction,
                reference = testY,
                positive = "Yes")
# Sensitivity has slightly increased for the Random forest model (69%). 

varImpPlot(rf)
# same variable importance as the individual tree. 

# partial dependence plot of the model
par(mfrow = c(2, 2))
partialPlot(rf, trainX, new_user, "Yes")
partialPlot(rf, trainX, age, "Yes")
partialPlot(rf, trainX, country, "Yes")
partialPlot(rf, trainX, source, "Yes")

# Old Users convert more easily 

# tune rf model
# setup ctrl object
ctrl <- trainControl(method = "cv",
                     number = 3,
                     summaryFunction = twoClassSummary,
                     classProbs = TRUE)

# fit a random forest model
set.seed(476)
rfGrid = data.frame(.mtry = 2:5)
rfModel <- train(x = trainX,
                 y = trainY,
                 method = "ranger",
                 tuneGrid = rfGrid,
                 trControl = ctrl,
                 num.trees = 100)
rfModel
# The final Random Forest Model selected has mtry = 2 with 100 trees in the ensemble.