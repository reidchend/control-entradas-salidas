import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { JWT } from "https://esm.sh/google-auth-library@9"

serve(async (req) => {
  try {
    // 1. Obtener las variables de entorno que configuramos antes
    const project_id = Deno.env.get("FIREBASE_PROJECT_ID")
    const client_email = Deno.env.get("FIREBASE_CLIENT_EMAIL")
    const private_key = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replace(/\\n/g, '\n')

    // 2. Autenticarse con Google para obtener un Token temporal de acceso
    const jwtClient = new JWT(
      client_email,
      null,
      private_key,
      ['https://www.googleapis.com/auth/cloud-platform']
    );
    const gTokens = await jwtClient.authorize();
    const accessToken = gTokens.access_token;

    // 3. Recibir los datos de la notificación (Título, Cuerpo y Token del destino)
    // Estos datos vendrán desde tu app de Flet o de un Trigger de la DB
    const { title, body, device_token } = await req.json()

    // 4. Construir la petición hacia Firebase Cloud Messaging (V1 API)
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: device_token,
            notification: { title, body },
            android: { priority: "high" }
          },
        }),
      }
    )

    const result = await res.json()
    return new Response(JSON.stringify(result), { headers: { "Content-Type": "application/json" } })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})