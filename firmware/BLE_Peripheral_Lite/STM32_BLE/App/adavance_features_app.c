/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    Adavance_features_app.c
  * @author  MCD Application Team
  * @brief   Adavance_features_app application definition.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "app_common.h"
#include "app_ble.h"
#include "ble.h"
#include "adavance_features_app.h"
#include "adavance_features.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/

/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

typedef enum
{
  /* USER CODE BEGIN Service2_APP_SendInformation_t */

  /* USER CODE END Service2_APP_SendInformation_t */
  ADAVANCE_FEATURES_APP_SENDINFORMATION_LAST
} ADAVANCE_FEATURES_APP_SendInformation_t;

typedef struct
{
  /* USER CODE BEGIN Service2_APP_Context_t */

  /* USER CODE END Service2_APP_Context_t */
  uint16_t              ConnectionHandle;
} ADAVANCE_FEATURES_APP_Context_t;

/* Private defines -----------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* External variables --------------------------------------------------------*/
/* USER CODE BEGIN EV */

/* USER CODE END EV */

/* Private macros ------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
static ADAVANCE_FEATURES_APP_Context_t ADAVANCE_FEATURES_APP_Context;

uint8_t a_ADAVANCE_FEATURES_UpdateCharData[247];

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/

/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Functions Definition ------------------------------------------------------*/
void ADAVANCE_FEATURES_Notification(ADAVANCE_FEATURES_NotificationEvt_t *p_Notification)
{
  /* USER CODE BEGIN Service2_Notification_1 */

  /* USER CODE END Service2_Notification_1 */
  switch(p_Notification->EvtOpcode)
  {
    /* USER CODE BEGIN Service2_Notification_Service2_EvtOpcode */

    /* USER CODE END Service2_Notification_Service2_EvtOpcode */

    case ADAVANCE_FEATURES_VERSION_READ_EVT:
      /* USER CODE BEGIN Service2Char1_READ_EVT */

      /* USER CODE END Service2Char1_READ_EVT */
      break;

    default:
      /* USER CODE BEGIN Service2_Notification_default */

      /* USER CODE END Service2_Notification_default */
      break;
  }
  /* USER CODE BEGIN Service2_Notification_2 */

  /* USER CODE END Service2_Notification_2 */
  return;
}

void ADAVANCE_FEATURES_APP_EvtRx(ADAVANCE_FEATURES_APP_ConnHandleNotEvt_t *p_Notification)
{
  /* USER CODE BEGIN Service2_APP_EvtRx_1 */

  /* USER CODE END Service2_APP_EvtRx_1 */

  switch(p_Notification->EvtOpcode)
  {
    /* USER CODE BEGIN Service2_APP_EvtRx_Service2_EvtOpcode */

    /* USER CODE END Service2_APP_EvtRx_Service2_EvtOpcode */
    case ADAVANCE_FEATURES_CONN_HANDLE_EVT :
      ADAVANCE_FEATURES_APP_Context.ConnectionHandle = p_Notification->ConnectionHandle;
      /* USER CODE BEGIN Service2_APP_CENTR_CONN_HANDLE_EVT */

      /* USER CODE END Service2_APP_CENTR_CONN_HANDLE_EVT */
      break;
    case ADAVANCE_FEATURES_DISCON_HANDLE_EVT :
      ADAVANCE_FEATURES_APP_Context.ConnectionHandle = 0xFFFF;
      /* USER CODE BEGIN Service2_APP_DISCON_HANDLE_EVT */

      /* USER CODE END Service2_APP_DISCON_HANDLE_EVT */
      break;

    default:
      /* USER CODE BEGIN Service2_APP_EvtRx_default */

      /* USER CODE END Service2_APP_EvtRx_default */
      break;
  }

  /* USER CODE BEGIN Service2_APP_EvtRx_2 */

  /* USER CODE END Service2_APP_EvtRx_2 */

  return;
}

void ADAVANCE_FEATURES_APP_Init(void)
{
  ADAVANCE_FEATURES_APP_Context.ConnectionHandle = 0xFFFF;
  ADAVANCE_FEATURES_Init();

  /* USER CODE BEGIN Service2_APP_Init */

  /* USER CODE END Service2_APP_Init */
  return;
}

void ADAVANCE_FEATURES_APP_Process(void)
{
  /* USER CODE BEGIN ADAVANCE_FEATURES_APP_Process_1 */

  /* USER CODE END ADAVANCE_FEATURES_APP_Process_1 */
  return;
}

/* USER CODE BEGIN FD */

/* USER CODE END FD */

/*************************************************************
 *
 * LOCAL FUNCTIONS
 *
 *************************************************************/

/* USER CODE BEGIN FD_LOCAL_FUNCTIONS*/

/* USER CODE END FD_LOCAL_FUNCTIONS*/
