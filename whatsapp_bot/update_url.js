const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://uyyyveojjvbxhuhbnype.supabase.co';
const supabaseKey = 'sb_publishable_PSAgKL3D297u8QY-G-SNuw_kcKWdCu5';

const supabase = createClient(supabaseUrl, supabaseKey);

async function updateBotUrl(url) {
  const { error } = await supabase
    .from('bot_config')
    .upsert({ key: 'bot_url', value: url, updated_at: new Date().toISOString() }, { onConflict: 'key' });

  if (error) {
    console.error('Error updating bot URL:', error);
    return false;
  }
  console.log(`[URL] Bot URL updated to: ${url}`);
  return true;
}

module.exports = { updateBotUrl };

if (require.main === module) {
  const url = process.argv[2];
  if (!url) {
    console.error('Usage: node update_url.js <url>');
    process.exit(1);
  }
  updateBotUrl(url).then(ok => process.exit(ok ? 0 : 1));
}
