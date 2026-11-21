/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2024 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32wb0x_hal.h"
#include "app_entry.h"
#include "app_common.h"
#include "app_debug.h"
#include "compiler.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "stm32wb0x_nucleo.h"
/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */
#define PASSWORD_SIZE 8
extern volatile bool relay_status;
extern volatile uint64_t serial_num;
void Timer16_Callback(void);
HAL_StatusTypeDef EEPROM_WriteSerialNumber(uint64_t serial);
/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define relay_en_Pin GPIO_PIN_3
#define relay_en_GPIO_Port GPIOB
#define relay_set_Pin GPIO_PIN_2
#define relay_set_GPIO_Port GPIOB
#define relay_reset_Pin GPIO_PIN_1
#define relay_reset_GPIO_Port GPIOB
#define led_r_Pin GPIO_PIN_0
#define led_r_GPIO_Port GPIOA
#define led_g_Pin GPIO_PIN_8
#define led_g_GPIO_Port GPIOA
#define button_Pin GPIO_PIN_9
#define button_GPIO_Port GPIOA
#define ee_en_Pin GPIO_PIN_5
#define ee_en_GPIO_Port GPIOB

/* USER CODE BEGIN Private defines */


/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
