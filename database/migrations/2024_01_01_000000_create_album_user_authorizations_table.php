<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('album_user_authorizations', function (Blueprint $table) {
            $table->engine = 'InnoDB';
            $table->charset = 'utf8mb4';
            $table->collation = 'utf8mb4_unicode_ci';
            $table->id();
            $table->foreignId('album_id')
                ->comment('相册ID')
                ->constrained('albums')
                ->onDelete('cascade');
            $table->foreignId('user_id')
                ->comment('被授权用户ID')
                ->constrained('users')
                ->onDelete('cascade');
            $table->timestamps();

            // 同一用户对同一相册只能有一条授权记录
            $table->unique(['album_id', 'user_id']);
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('album_user_authorizations');
    }
};
