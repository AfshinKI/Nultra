/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    Peripheral_Lite_Server_app.c
  * @author  MCD Application Team
  * @brief   Peripheral_Lite_Server_app application definition.
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

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "app_common.h"
#include "app_ble.h"
#include "ble.h"
#include "peripheral_lite_server_app.h"
#include "peripheral_lite_server.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/

/* USER CODE BEGIN PTD */
 typedef struct{
    uint8_t             Device_Led_Selection;
    uint8_t             Led1;
 }P2P_LedCharValue_t;


/* USER CODE END PTD */

typedef enum
{
  Switch_c_NOTIFICATION_OFF,
  Switch_c_NOTIFICATION_ON,
  /* USER CODE BEGIN Service1_APP_SendInformation_t */

  /* USER CODE END Service1_APP_SendInformation_t */
  PERIPHERAL_LITE_SERVER_APP_SENDINFORMATION_LAST
} PERIPHERAL_LITE_SERVER_APP_SendInformation_t;

typedef struct
{
  PERIPHERAL_LITE_SERVER_APP_SendInformation_t     Switch_c_Notification_Status;
  /* USER CODE BEGIN Service1_APP_Context_t */
  P2P_LedCharValue_t              LedControl;
  /* USER CODE END Service1_APP_Context_t */
  uint16_t              ConnectionHandle;
} PERIPHERAL_LITE_SERVER_APP_Context_t;

/* Private defines -----------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* External variables --------------------------------------------------------*/
/* USER CODE BEGIN EV */
extern BleApplicationContext_t bleAppContext;
/* USER CODE END EV */

/* Private macros ------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
static PERIPHERAL_LITE_SERVER_APP_Context_t PERIPHERAL_LITE_SERVER_APP_Context;

uint8_t a_PERIPHERAL_LITE_SERVER_UpdateCharData[247];

/* USER CODE BEGIN PV */
//void BLE_LED_CharWrite_Callback(uint8_t new_value)
//{
//  // Set the global flag based on the value written via BLE
//	relay_status = (new_value != 0);
//}
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
static void PERIPHERAL_LITE_SERVER_Switch_c_SendNotification(void);

/* USER CODE BEGIN PFP */
static void PERIPHERAL_LITE_SERVER_APP_LED_context_Init(void);
/* USER CODE END PFP */

/* Functions Definition ------------------------------------------------------*/
void PERIPHERAL_LITE_SERVER_Notification(PERIPHERAL_LITE_SERVER_NotificationEvt_t *p_Notification)
{
  /* USER CODE BEGIN Service1_Notification_1 */

  /* USER CODE END Service1_Notification_1 */
  switch(p_Notification->EvtOpcode)
  {
    /* USER CODE BEGIN Service1_Notification_Service1_EvtOpcode */

    /* USER CODE END Service1_Notification_Service1_EvtOpcode */

    case PERIPHERAL_LITE_SERVER_SWITCH_READ_EVT:
      /* USER CODE BEGIN Service1Char1_READ_EVT */

      /* USER CODE END Service1Char1_READ_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SWITCH_WRITE_NO_RESP_EVT:
      /* USER CODE BEGIN Service1Char1_WRITE_NO_RESP_EVT */
      if((p_Notification->DataTransfered.p_Payload[0] == 0x01)&&(password_verified==1))
      {
    	relay_status = true;
        APP_DBG_MSG("-- PERIPHERAL LITE APPLICATION SERVER : LED1/Blue ON\n"); 
        PERIPHERAL_LITE_SERVER_APP_Context.LedControl.Led1 = 0x01; /* LED1 ON */
      }
      if((p_Notification->DataTransfered.p_Payload[0] == 0x00)&&(password_verified==1))
      {
    	relay_status = false;
        APP_DBG_MSG("-- PERIPHERAL LITE APPLICATION SERVER : LED1/Blue OFF\n"); 
        PERIPHERAL_LITE_SERVER_APP_Context.LedControl.Led1 = 0x00; /* LED1 OFF */
      }
      PERIPHERAL_LITE_SERVER_Data_t relay_statusData;
      relay_statusData.p_Payload = (uint64_t *)&relay_status;
      relay_statusData.Length = sizeof(relay_status);

      PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SWITCH, &relay_statusData);
      /* USER CODE END Service1Char1_WRITE_NO_RESP_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SWITCH_WRITE_EVT:
      /* USER CODE BEGIN Service1Char1_WRITE_EVT */

      /* USER CODE END Service1Char1_WRITE_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SWITCH_C_NOTIFY_ENABLED_EVT:
      /* USER CODE BEGIN Service1Char2_NOTIFY_ENABLED_EVT */
      PERIPHERAL_LITE_SERVER_APP_Context.Switch_c_Notification_Status = Switch_c_NOTIFICATION_ON;
      APP_DBG_MSG("-- PERIPHERAL LITE APPLICATION SERVER : NOTIFICATION ENABLED\n"); 
      APP_DBG_MSG(" \n\r");
      /* USER CODE END Service1Char2_NOTIFY_ENABLED_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SWITCH_C_NOTIFY_DISABLED_EVT:
      /* USER CODE BEGIN Service1Char2_NOTIFY_DISABLED_EVT */
      PERIPHERAL_LITE_SERVER_APP_Context.Switch_c_Notification_Status = Switch_c_NOTIFICATION_OFF;
      APP_DBG_MSG("-- PERIPHERAL LITE APPLICATION SERVER : NOTIFICATION DISABLED\n"); 
      APP_DBG_MSG(" \n\r");
      /* USER CODE END Service1Char2_NOTIFY_DISABLED_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_VBATT_READ_EVT:
      /* USER CODE BEGIN Service1Char3_READ_EVT */

      /* USER CODE END Service1Char3_READ_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SERIAL_NUM_READ_EVT:
      /* USER CODE BEGIN Service1Char4_READ_EVT */

      /* USER CODE END Service1Char4_READ_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_SERIAL_NUM_WRITE_EVT:
      /* USER CODE BEGIN Service1Char4_WRITE_EVT */

        // Only allow updating the serial number if the password has been verified.
        if (!password_verified) {
            APP_DBG_MSG("Password not verified. Cannot update serial number.\n");
            // Optionally, you could notify the client about the failure.
            // Update the GATT database so that subsequent reads return the new value.
            PERIPHERAL_LITE_SERVER_Data_t serial_numData;
            serial_numData.p_Payload = (uint8_t *)&serial_num;
            serial_numData.Length = sizeof(serial_num);
            PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SERIAL_NUM, &serial_numData);
            break;
        }

        // Check that the write event payload length is 8 bytes
        if (p_Notification->DataTransfered.Length == 11) {
            uint64_t newSerial = 0;
            // Assuming the serial number is sent in Big-Endian format:
            for (int i = 7; i >= 0; i--) {
                newSerial = (newSerial << 8) | p_Notification->DataTransfered.p_Payload[i];
            }
            // Update your global serial number variable
            serial_num = newSerial;

            // Optionally, store the new serial number in EEPROM
            if (EEPROM_WriteSerialNumber(serial_num) != HAL_OK) {
                APP_DBG_MSG("Failed to store serial number to EEPROM\n");
            } else {
                APP_DBG_MSG("Serial number updated to: 0x%llX\n", serial_num);
            }

            // Update the GATT database so that subsequent reads return the new value.
            PERIPHERAL_LITE_SERVER_Data_t serial_numData;
            serial_numData.p_Payload = (uint8_t *)&serial_num;
            serial_numData.Length = sizeof(serial_num);
            PERIPHERAL_LITE_SERVER_UpdateValue(PERIPHERAL_LITE_SERVER_SERIAL_NUM, &serial_numData);
        }
      /* USER CODE END Service1Char4_WRITE_EVT */
      break;

    case PERIPHERAL_LITE_SERVER_PASSWORD_WRITE_EVT:
      /* USER CODE BEGIN Service1Char5_WRITE_EVT */
        // Check if the payload length matches the expected password size.
        if (p_Notification->DataTransfered.Length == PASSWORD_SIZE) {
            // Copy the received password to our global variable.
            memcpy(user_password_received, p_Notification->DataTransfered.p_Payload, PASSWORD_SIZE);
            // Compare the received password with the expected one.
            if (memcmp(user_password_received, expected_password, PASSWORD_SIZE) == 0) {
                password_verified = true;
                APP_DBG_MSG("Password verified.\n");
                // Optionally, store the password in EEPROM if needed:
                // EEPROM_Write(PASSWORD_EEPROM_ADDRESS, user_password_received, PASSWORD_SIZE);
            } else {
                password_verified = false;
                APP_DBG_MSG("Incorrect password.\n");
            }
        } else {
            APP_DBG_MSG("Password write error: incorrect data length.\n");
        }
      /* USER CODE END Service1Char5_WRITE_EVT */
      break;

    default:
      /* USER CODE BEGIN Service1_Notification_default */

      /* USER CODE END Service1_Notification_default */
      break;
  }
  /* USER CODE BEGIN Service1_Notification_2 */

  /* USER CODE END Service1_Notification_2 */
  return;
}

void PERIPHERAL_LITE_SERVER_APP_EvtRx(PERIPHERAL_LITE_SERVER_APP_ConnHandleNotEvt_t *p_Notification)
{
  /* USER CODE BEGIN Service1_APP_EvtRx_1 */

  /* USER CODE END Service1_APP_EvtRx_1 */

  switch(p_Notification->EvtOpcode)
  {
    /* USER CODE BEGIN Service1_APP_EvtRx_Service1_EvtOpcode */

    /* USER CODE END Service1_APP_EvtRx_Service1_EvtOpcode */
    case PERIPHERAL_LITE_SERVER_CONN_HANDLE_EVT :
      PERIPHERAL_LITE_SERVER_APP_Context.ConnectionHandle = p_Notification->ConnectionHandle;
      /* USER CODE BEGIN Service1_APP_CENTR_CONN_HANDLE_EVT */
      password_verified = false;
      /* USER CODE END Service1_APP_CENTR_CONN_HANDLE_EVT */
      break;
    case PERIPHERAL_LITE_SERVER_DISCON_HANDLE_EVT :
      PERIPHERAL_LITE_SERVER_APP_Context.ConnectionHandle = 0xFFFF;
      /* USER CODE BEGIN Service1_APP_DISCON_HANDLE_EVT */
      password_verified = false;
      PERIPHERAL_LITE_SERVER_APP_LED_context_Init();
      /* USER CODE END Service1_APP_DISCON_HANDLE_EVT */
      break;

    default:
      /* USER CODE BEGIN Service1_APP_EvtRx_default */

      /* USER CODE END Service1_APP_EvtRx_default */
      break;
  }

  /* USER CODE BEGIN Service1_APP_EvtRx_2 */

  /* USER CODE END Service1_APP_EvtRx_2 */

  return;
}

void PERIPHERAL_LITE_SERVER_APP_Init(void)
{
  PERIPHERAL_LITE_SERVER_APP_Context.ConnectionHandle = 0xFFFF;
  PERIPHERAL_LITE_SERVER_Init();

  /* USER CODE BEGIN Service1_APP_Init */
  /**
   * Initialize Led Service
   */
  PERIPHERAL_LITE_SERVER_APP_Context.Switch_c_Notification_Status= Switch_c_NOTIFICATION_OFF;
  PERIPHERAL_LITE_SERVER_APP_LED_context_Init();
  /* USER CODE END Service1_APP_Init */
  return;
}

void PERIPHERAL_LITE_SERVER_APP_Process(void)
{
  /* USER CODE BEGIN PERIPHERAL_LITE_SERVER_APP_Process_1 */

  if (bleAppContext.restartAdv)
  {
    bleAppContext.restartAdv = FALSE; 
    
    APP_BLE_Procedure_Gap_Peripheral(PROC_GAP_PERIPH_ADVERTISE_START_FAST); 
  }
  /* Notification flow every ~ 1 sec */
  if (bleAppContext.is_notification_timer_expired)
  {
    bleAppContext.is_notification_timer_expired = FALSE; 
    PERIPHERAL_LITE_SERVER_Switch_c_SendNotification();
    
    /* Restart a timer for sending notification from server to client   */
    HAL_RADIO_TIMER_StartVirtualTimer(&bleAppContext.Notification_mgr_timer_Id, NOTIFICATION_TIMEOUT_MS);
  }
  /* Led blinking rate */
  if (bleAppContext.is_adv_connection_timer_expired)
  {
     bleAppContext.is_adv_connection_timer_expired = FALSE; 
     if (bleAppContext.BleApplicationContext_legacy.connectionHandle == 0xFFFF)
     {
       /* Start a timer for slow led blinking for advertising  */
       HAL_RADIO_TIMER_StartVirtualTimer(&bleAppContext.Advertising_mgr_timer_Id, ADV_TIMEOUT_MS);
     }
     else
     {
       /* Start a timer for fast  led blinking for connection  */
       HAL_RADIO_TIMER_StartVirtualTimer(&bleAppContext.Advertising_mgr_timer_Id, CONN_TIMEOUT_MS);
     }
  }
  
  /* USER CODE END PERIPHERAL_LITE_SERVER_APP_Process_1 */
  return;
}

/* USER CODE BEGIN FD */
void PERIPHERAL_LITE_SERVER_APP_LED_context_Init(void)
{
//  BSP_LED_Off(LED_BLUE);
//  PERIPHERAL_LITE_SERVER_APP_Context.LedControl.Device_Led_Selection=0x01; /* Device1 */
//  PERIPHERAL_LITE_SERVER_APP_Context.LedControl.Led1=0x00; /* led OFF */

  return;
}
/* USER CODE END FD */

/*************************************************************
 *
 * LOCAL FUNCTIONS
 *
 *************************************************************/
__USED void PERIPHERAL_LITE_SERVER_Switch_c_SendNotification(void) /* Property Notification */
{
  PERIPHERAL_LITE_SERVER_APP_SendInformation_t notification_on_off = Switch_c_NOTIFICATION_OFF;
  PERIPHERAL_LITE_SERVER_Data_t peripheral_lite_server_notification_data;

  peripheral_lite_server_notification_data.p_Payload = (uint8_t*)a_PERIPHERAL_LITE_SERVER_UpdateCharData;
  peripheral_lite_server_notification_data.Length = 0;

  /* USER CODE BEGIN Service1Char2_NS_1*/

  
  if(password_verified)
	  a_PERIPHERAL_LITE_SERVER_UpdateCharData[0] = relay_status;
  else
	  a_PERIPHERAL_LITE_SERVER_UpdateCharData[0] = 0xFF;
  /* Update notification data length */
  peripheral_lite_server_notification_data.Length = (peripheral_lite_server_notification_data.Length)+1;

  if(PERIPHERAL_LITE_SERVER_APP_Context.Switch_c_Notification_Status == Switch_c_NOTIFICATION_ON)
  { 
    APP_DBG_MSG("-- P2P APPLICATION SERVER : INFORM CLIENT BUTTON 1 PUSHED\n");
    notification_on_off = Switch_c_NOTIFICATION_ON;
  } 
  else
  {
    APP_DBG_MSG("-- P2P APPLICATION SERVER : CAN'T INFORM CLIENT - NOTIFICATION DISABLED\n"); 
  }

  /* USER CODE END Service1Char2_NS_1*/

  if (notification_on_off != Switch_c_NOTIFICATION_OFF && PERIPHERAL_LITE_SERVER_APP_Context.ConnectionHandle != 0xFFFF)
  {
    PERIPHERAL_LITE_SERVER_NotifyValue(PERIPHERAL_LITE_SERVER_SWITCH_C, &peripheral_lite_server_notification_data, PERIPHERAL_LITE_SERVER_APP_Context.ConnectionHandle);
  }

  /* USER CODE BEGIN Service1Char2_NS_Last*/

  /* USER CODE END Service1Char2_NS_Last*/

  return;
}

/* USER CODE BEGIN FD_LOCAL_FUNCTIONS*/

/* USER CODE END FD_LOCAL_FUNCTIONS*/
