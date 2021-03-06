#Note: Although the revised denseNet can support image with any size,
#but it also have some limitation because its architecture. The image
#size must be resized to multiple of 32.

library(mxnet)
library(imager)

#Load pre-trained model & image

Dense_model = mx.model.load('model/densenet-imagenet-169-0', 125)

img_path = paste0('image/informal image.jpg')
img <- load.image(img_path)

#Function

CAM = function (img, show.object = 1, chinese_label = FALSE) {
  
  require(EBImage)  
  require(magrittr)
  
  #Resized the image
  
  dim_img <- dim(img)
  if (dim_img[1] <= dim_img[2]) {
    dim_img[2] = dim_img[2]/dim_img[1]*224
    dim_img[1] = 224
  } else {
    dim_img[1] = dim_img[1]/dim_img[2]*224
    dim_img[2] = 224
  }
  dim_x <- round(dim_img[1]/32) * 32
  dim_y <- round(dim_img[2]/32) * 32
  
  resized_img <- resize(img, dim_x, dim_y)
  X = array(resized_img, dim = c(dim_x, dim_y, 3, 1)) * 256
  
  #Visualization
  
  if (show.object < 1) {
    stop('Please enter a value of show.object from 1 to 5.')
  } else if (show.object == 1) {
    par(mai = rep(0, 4), mfrow = c(1, 2))
  } else if (show.object <= 3) {
    par(mai = rep(0, 4), mfrow = c(2, 2))
  } else if (show.object <= 5) {
    par(mai = rep(0, 4), mfrow = c(2, 3))
  } else {.
    stop('You cannot show more than 5 predictions in single plot, please modify this function.')
  }

  plot(resized_img, axes = FALSE)
  img <- resized_img %>% grayscale()
  
  #Extract the feature map from DenseNet
  
  all_layers = Dense_model$symbol$get.internals()
  relu1_output = which(all_layers$outputs == 'relu1_output') %>% all_layers$get.output()
  pool1_output = mx.symbol.mean(relu1_output, axis = c(2, 3), name = 'pool1_output')
  fc1 = mx.symbol.FullyConnected(pool1_output, name = 'fc1', num.hidden = 1000)
  softmax = mx.symbol.SoftmaxOutput(fc1, name = 'softmax')
  
  #Note-1: 'tail(all_layers$outputs, 20)' can be used to understand the last few layers of your network.
  #Note-2: 'mx.symbol.infer.shape(relu1_output, data = c(dim_x, dim_y, 3, 1))$out.shapes' can be used to
  #        understand output shape of the intrested layer.
  
  out = mx.symbol.Group(c(relu1_output, softmax))
  executor = mx.simple.bind(symbol = out, data = c(dim_x, dim_y, 3, 1), ctx = mx.cpu())
  
  mx.exec.update.arg.arrays(executor, Dense_model$arg.params, match.name = TRUE)
  mx.exec.update.aux.arrays(executor, Dense_model$aux.params, match.name = TRUE)
  mx.exec.update.arg.arrays(executor, list(data = mx.nd.array(X)), match.name = TRUE)
  mx.exec.forward(executor, is.train = FALSE)
  
  #Get the weights in final fully connected layer
  
  FC_weight = as.array(Dense_model$arg.params$fc1_weight)
  
  #Get the feature maps from last convolution layer
  
  feature = as.array(executor$ref.outputs$relu1_output)
  
  #Get the prediction output
  
  pred_prob = as.array(executor$ref.outputs$softmax_output)
  pred_pos = order(pred_prob, decreasing = TRUE)[1:show.object]
  if (chinese_label) {
    label_names = readLines('model/chinese synset.txt')
  } else {
    label_names = readLines('model/synset.txt')
  }
  Encoding(label_names) = 'UTF-8'
  print(paste0(label_names[pred_pos], ' (prob = ', formatC(pred_prob[pred_pos], 3, format = 'f'), ')'))
  
  #Weithged sum of feature map: the core of class activation mapping (CAM)
  
  CAM_list = list()
  
  for (j in 1:show.object) {
    for (i in 1:1664) {
      if (i == 1) {
        CAM_list[[j]] = feature[,,i,] * FC_weight[i, pred_pos[j]] 
      } else {
        CAM_list[[j]] = CAM_list[[j]] + feature[,,i,] * FC_weight[i, pred_pos[j]] 
      }
    }
    #Standardization from 0 to 1
    CAM_list[[j]] = (CAM_list[[j]] - min(CAM_list[[j]]))/(max(CAM_list[[j]]) - min(CAM_list[[j]])) 
  }
  
  #Define the color
  
  cols <-  colorRampPalette(c("#000099", "#00FEFF", "#45FE4F", 
                              "#FCFF00", "#FF9400", "#FF3100"))(256)
  
  #Enlarge the class activation mapping and fuzzification
  
  w = makeBrush(size = 7, shape = 'gaussian', sigma = 2)
  
  Resized_CAM_list = list()
  
  for (j in 1:show.object) {
    Resized_CAM_list[[j]] = EBImage::resize(CAM_list[[j]], dim_x, dim_y) %>% filter2(., w)
    Resized_CAM_list[[j]] = round(Resized_CAM_list[[j]]*255)+1 %>% as.integer()
    Resized_CAM_list[[j]] = cols[Resized_CAM_list[[j]]] %>% paste0(., "80") %>% matrix(., dim_x, dim_y) %>% .[,dim_y:1] %>% t() %>% as.raster()
  }
  
  #Visualization and show the prediction output
  
  for (j in 1:show.object) {
    plot(img, axes = FALSE)
    plot(Resized_CAM_list[[j]], add = TRUE)
    obj = label_names[pred_pos[j]]
    legend('bottomright', paste0(substr(obj, 11, nchar(obj)), ' (prob = ', formatC(pred_prob[pred_pos[j]], 3, format = 'f'), ')'), bg = 'gray90')
  }
  
}

#Use this function!

CAM(img, show.object = 5, chinese_label = FALSE)
